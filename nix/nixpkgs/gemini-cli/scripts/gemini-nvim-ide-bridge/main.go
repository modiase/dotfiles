package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"

	devlogs "devlogs-lib"

	"github.com/neovim/go-client/nvim"
)

var (
	logger            *devlogs.Logger
	tmuxNvimSelectBin = "tmux-nvim-select"
)

type JSONRPCRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
	ID      any             `json:"id"`
}

type JSONRPCResponse struct {
	JSONRPC string `json:"jsonrpc"`
	Result  any    `json:"result,omitempty"`
	Error   any    `json:"error,omitempty"`
	ID      any    `json:"id"`
}

type IDEInfo struct {
	Name        string `json:"name"`
	DisplayName string `json:"displayName"`
}

type DiscoveryConfig struct {
	Port          int     `json:"port"`
	WorkspacePath string  `json:"workspacePath"`
	AuthToken     string  `json:"authToken"`
	IDEInfo       IDEInfo `json:"ideInfo"`
}

type Bridge struct {
	nvimClient *nvim.Nvim
	socketPath string
	port       int
	authToken  string
	mu         sync.RWMutex
}

func (b *Bridge) connectNvim(socketPath string) error {
	v, err := nvim.Dial(socketPath)
	if err != nil {
		return err
	}
	_ = v.RegisterHandler("NVIM_MCP_DiagnosticsChanged", func() {})
	b.mu.Lock()
	if b.nvimClient != nil {
		_ = b.nvimClient.Close()
	}
	b.nvimClient = v
	b.socketPath = socketPath
	b.mu.Unlock()
	return nil
}

func (b *Bridge) getNvim() (*nvim.Nvim, error) {
	b.mu.RLock()
	defer b.mu.RUnlock()
	if b.nvimClient == nil {
		return nil, fmt.Errorf("nvim not connected")
	}
	return b.nvimClient, nil
}

func (b *Bridge) discoverSocket() string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, tmuxNvimSelectBin, "-q")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(strings.TrimSpace(string(output)), "\n") {
		if strings.HasPrefix(line, "NVIM_SOCKET=") {
			return strings.TrimPrefix(line, "NVIM_SOCKET=")
		}
	}
	return ""
}

func (b *Bridge) connectLoop() {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for range ticker.C {
		b.healthCheckAndReconnect()
	}
}

func (b *Bridge) pingNvim(v *nvim.Nvim) bool {
	ch := make(chan error, 1)
	go func() {
		var result int
		ch <- v.Eval("1", &result)
	}()
	select {
	case err := <-ch:
		return err == nil
	case <-time.After(2 * time.Second):
		return false
	}
}

func (b *Bridge) healthCheckAndReconnect() {
	b.mu.RLock()
	v := b.nvimClient
	socket := b.socketPath
	b.mu.RUnlock()

	if v != nil {
		if fileExists(socket) && b.pingNvim(v) {
			return
		}
		logger.Info(fmt.Sprintf("nvim disconnected socket=%s", socket))
		b.mu.Lock()
		if b.nvimClient == v {
			_ = b.nvimClient.Close()
			b.nvimClient = nil
			b.socketPath = ""
		}
		b.mu.Unlock()
	}

	discovered := b.discoverSocket()
	if discovered == "" {
		return
	}

	if err := b.connectNvim(discovered); err != nil {
		logger.Warn(fmt.Sprintf("dial failed socket=%s err=%v", discovered, err))
		return
	}
	logger.Info(fmt.Sprintf("connected socket=%s", discovered))
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (b *Bridge) handleSSE(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "SSE not supported", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	msgURL := fmt.Sprintf("http://localhost:%d/mcp", b.port)
	_, _ = fmt.Fprintf(w, "event: endpoint\ndata: %s\n\n", msgURL)
	flusher.Flush()

	ctx := r.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case <-time.After(15 * time.Second):
			_, _ = fmt.Fprintf(w, ": keep-alive\n\n")
			flusher.Flush()
		}
	}
}

func (b *Bridge) handleMCP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodOptions {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.WriteHeader(http.StatusNoContent)
		return
	}

	w.Header().Set("Access-Control-Allow-Origin", "*")

	authHeader := r.Header.Get("Authorization")
	if !strings.HasPrefix(authHeader, "Bearer ") || strings.TrimPrefix(authHeader, "Bearer ") != b.authToken {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req JSONRPCRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	var result any
	var err error

	switch req.Method {
	case "initialize":
		result = map[string]any{
			"protocolVersion": "2024-11-05",
			"capabilities":    map[string]any{},
			"serverInfo": map[string]string{
				"name":    "gemini-nvim-ide-bridge",
				"version": "0.2.0",
			},
		}
	case "tools/list":
		result = map[string]any{
			"tools": []map[string]any{
				{
					"name":        "get_active_editor_context",
					"description": "Get context from the active editor",
					"inputSchema": map[string]any{"type": "object", "properties": map[string]any{}},
				},
				{
					"name":        "open_file",
					"description": "Open a file in the editor",
					"inputSchema": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"path": map[string]any{"type": "string"},
						},
						"required": []string{"path"},
					},
				},
				{
					"name":        "openDiff",
					"description": "Open a diff view",
					"inputSchema": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"filePath":   map[string]any{"type": "string"},
							"newContent": map[string]any{"type": "string"},
						},
						"required": []string{"filePath", "newContent"},
					},
				},
				{
					"name":        "closeDiff",
					"description": "Close a diff view",
					"inputSchema": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"filePath":             map[string]any{"type": "string"},
							"suppressNotification": map[string]any{"type": "boolean"},
						},
						"required": []string{"filePath"},
					},
				},
				{
					"name":        "get_diagnostics",
					"description": "Get LSP diagnostics (errors and warnings) from the editor",
					"inputSchema": map[string]any{
						"type": "object",
						"properties": map[string]any{
							"uri": map[string]any{
								"type":        "string",
								"description": "File path to filter diagnostics for. Omit for all files.",
							},
						},
					},
				},
			},
		}
	case "tools/call":
		var params struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err = json.Unmarshal(req.Params, &params); err == nil {
			logger.Info(fmt.Sprintf("tool call=%s", params.Name))
			switch params.Name {
			case "get_active_editor_context":
				result, err = b.getActiveEditorContext()
			case "open_file":
				result, err = b.openFile(params.Arguments)
			case "openDiff":
				result, err = b.openDiff(params.Arguments)
			case "closeDiff":
				result, err = b.closeDiff(params.Arguments)
			case "get_diagnostics":
				result, err = b.getDiagnostics(params.Arguments)
			default:
				err = fmt.Errorf("tool not found: %s", params.Name)
			}
		} else {
			err = fmt.Errorf("invalid tool/call params")
		}
	default:
		err = fmt.Errorf("method not found: %s", req.Method)
	}

	if err != nil {
		logger.Error(fmt.Sprintf("method=%s err=%v", req.Method, err))
	}

	resp := JSONRPCResponse{
		JSONRPC: "2.0",
		ID:      req.ID,
	}

	if err != nil {
		resp.Error = map[string]any{
			"code":    -32603,
			"message": err.Error(),
		}
	} else {
		resp.Result = result
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

func toolResult(text string) map[string]any {
	return map[string]any{
		"content": []map[string]any{
			{"type": "text", "text": text},
		},
	}
}

func (b *Bridge) getActiveEditorContext() (any, error) {
	v, err := b.getNvim()
	if err != nil {
		return nil, err
	}

	var ctx struct {
		ActiveFilePath string   `json:"activeFilePath"`
		CursorLine     int      `json:"cursorLine"`
		CursorColumn   int      `json:"cursorColumn"`
		SelectedText   string   `json:"selectedText"`
		RecentFiles    []string `json:"recentFiles"`
	}

	buf, err := v.CurrentBuffer()
	if err != nil {
		return nil, err
	}

	name, err := v.BufferName(buf)
	if err != nil {
		return nil, err
	}
	ctx.ActiveFilePath = name

	win, err := v.CurrentWindow()
	if err != nil {
		return nil, err
	}

	pos, err := v.WindowCursor(win)
	if err != nil {
		return nil, err
	}
	ctx.CursorLine = pos[0]
	ctx.CursorColumn = pos[1]

	mode, err := v.Mode()
	if err == nil && (mode.Mode == "v" || mode.Mode == "V" || mode.Mode == "\x16") {
		var sel any
		err = v.Eval(`join(getregion(getpos("v"), getpos(".")), "\n")`, &sel)
		if err == nil {
			if s, ok := sel.(string); ok {
				ctx.SelectedText = s
			}
		}
	}

	bufs, err := v.Buffers()
	if err == nil {
		for _, b := range bufs {
			if b == buf {
				continue
			}
			bname, err := v.BufferName(b)
			if err != nil || bname == "" {
				continue
			}
			if strings.HasPrefix(bname, "term://") || strings.Contains(bname, "[") {
				continue
			}
			if !fileExists(bname) {
				continue
			}
			ctx.RecentFiles = append(ctx.RecentFiles, bname)
			if len(ctx.RecentFiles) >= 10 {
				break
			}
		}
	}

	data, _ := json.Marshal(ctx)
	return toolResult(string(data)), nil
}

func (b *Bridge) openFile(args json.RawMessage) (any, error) {
	v, err := b.getNvim()
	if err != nil {
		return nil, err
	}

	var p struct {
		Path string `json:"path"`
	}
	if err := json.Unmarshal(args, &p); err != nil {
		return nil, err
	}
	if err := v.Command("edit " + p.Path); err != nil {
		return nil, err
	}
	return toolResult("OK"), nil
}

func (b *Bridge) openDiff(args json.RawMessage) (any, error) {
	v, err := b.getNvim()
	if err != nil {
		return nil, err
	}

	var p struct {
		FilePath   string `json:"filePath"`
		NewContent string `json:"newContent"`
	}
	if err := json.Unmarshal(args, &p); err != nil {
		return nil, err
	}

	_ = v.Command("edit " + p.FilePath)

	newBuf, err := v.CreateBuffer(false, true)
	if err != nil {
		return nil, err
	}

	lines := strings.Split(p.NewContent, "\n")
	byteLines := make([][]byte, len(lines))
	for i, l := range lines {
		byteLines[i] = []byte(l)
	}

	_ = v.SetBufferLines(newBuf, 0, -1, true, byteLines)
	_ = v.SetBufferOption(newBuf, "buftype", "nofile")
	_ = v.SetBufferOption(newBuf, "bufhidden", "wipe")
	_ = v.SetBufferName(newBuf, "Proposed Changes")

	_ = v.Command("tabnew " + p.FilePath)
	_ = v.Command("diffthis")
	_ = v.Command("rightbelow vsplit")
	_ = v.SetCurrentBuffer(newBuf)
	_ = v.Command("diffthis")

	return toolResult("Diff opened in new tab"), nil
}

func (b *Bridge) closeDiff(args json.RawMessage) (any, error) {
	v, err := b.getNvim()
	if err != nil {
		return nil, err
	}

	_ = v.Command("tabclose")
	return toolResult("OK"), nil
}

func (b *Bridge) getDiagnostics(args json.RawMessage) (any, error) {
	v, err := b.getNvim()
	if err != nil {
		return nil, err
	}

	var p struct {
		URI string `json:"uri"`
	}
	_ = json.Unmarshal(args, &p)

	luaCode := `
local bufnr = nil
local uri = ...
if uri and uri ~= '' then
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b) == uri then bufnr = b; break end
  end
  if not bufnr then return '[]' end
end
local diags = vim.diagnostic.get(bufnr, {severity = {min = vim.diagnostic.severity.WARN}})
local result = {}
for _, d in ipairs(diags) do
  table.insert(result, {
    file = vim.api.nvim_buf_get_name(d.bufnr),
    line = d.lnum + 1,
    col = d.col + 1,
    severity = d.severity == 1 and 'error' or 'warning',
    message = d.message,
    source = d.source or '',
  })
end
return vim.json.encode(result)
`
	var resultJSON string
	if err := v.ExecLua(luaCode, &resultJSON, p.URI); err != nil {
		return nil, fmt.Errorf("diagnostics lua: %w", err)
	}

	return toolResult(resultJSON), nil
}

func main() {
	socketPath := flag.String("socket", "", "Path to Neovim socket")
	port := flag.Int("port", 0, "Port to listen on")
	idePidsStr := flag.String("ide-pids", "", "Space-separated candidate IDE PIDs")
	workspace := flag.String("workspace", "", "Workspace path")
	_ = flag.String("wrapper-id", "", "Wrapper instance identifier")
	flag.Parse()

	logger = devlogs.NewLogger("gemini-bridge")

	if *socketPath == "" {
		*socketPath = os.Getenv("NVIM_SOCKET")
	}

	if *workspace == "" {
		cwd, _ := os.Getwd()
		*workspace = cwd
	}

	if *idePidsStr == "" {
		*idePidsStr = os.Getenv("IDE_PIDS")
	}

	authToken := "nvim-mcp-token"

	bridge := &Bridge{
		port:      *port,
		authToken: authToken,
	}

	if *socketPath != "" {
		if err := bridge.connectNvim(*socketPath); err != nil {
			logger.Info(fmt.Sprintf("initial connect failed socket=%s err=%v", *socketPath, err))
		} else {
			logger.Info(fmt.Sprintf("connected socket=%s", *socketPath))
		}
	} else {
		logger.Info("no initial socket, waiting for discovery")
	}

	go bridge.connectLoop()

	var discoveryFiles []string
	if *idePidsStr != "" {
		pids := strings.Fields(*idePidsStr)
		discoveryDir := filepath.Join(os.TempDir(), "gemini", "ide")
		_ = os.MkdirAll(discoveryDir, 0755)

		for _, pid := range pids {
			discoveryFile := filepath.Join(discoveryDir, fmt.Sprintf("gemini-ide-server-%s-%d.json", pid, *port))
			config := DiscoveryConfig{
				Port:          *port,
				WorkspacePath: *workspace,
				AuthToken:     authToken,
				IDEInfo: IDEInfo{
					Name:        "vscode",
					DisplayName: "Neovim",
				},
			}
			data, _ := json.Marshal(config)
			_ = os.WriteFile(discoveryFile, data, 0644)
			discoveryFiles = append(discoveryFiles, discoveryFile)
		}
	}

	defer func() {
		for _, f := range discoveryFiles {
			_ = os.Remove(f)
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/sse", bridge.handleSSE)
	mux.HandleFunc("/mcp", bridge.handleMCP)

	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", *port),
		Handler: mux,
	}

	logger.Info(fmt.Sprintf("listening port=%d", *port))

	go func() {
		for {
			if os.Getppid() == 1 {
				os.Exit(0)
			}
			time.Sleep(2 * time.Second)
		}
	}()

	if err := server.ListenAndServe(); err != nil {
		logger.Error(fmt.Sprintf("server err=%v", err))
		os.Exit(1)
	}
}
