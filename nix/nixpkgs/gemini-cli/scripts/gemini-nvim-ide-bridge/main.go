package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/neovim/go-client/nvim"
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
	nvim       *nvim.Nvim
	socketPath string
	port       int
	authToken  string
}

func (b *Bridge) connectNvim() error {
	v, err := nvim.Dial(b.socketPath)
	if err != nil {
		return err
	}
	b.nvim = v
	return nil
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
				"version": "0.1.0",
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
			},
		}
	case "tools/call":
		var params struct {
			Name      string          `json:"name"`
			Arguments json.RawMessage `json:"arguments"`
		}
		if err = json.Unmarshal(req.Params, &params); err == nil {
			switch params.Name {
			case "get_active_editor_context":
				result, err = b.getActiveEditorContext()
			case "open_file":
				result, err = b.openFile(params.Arguments)
			case "openDiff":
				result, err = b.openDiff(params.Arguments)
			case "closeDiff":
				result, err = b.closeDiff(params.Arguments)
			default:
				err = fmt.Errorf("tool not found: %s", params.Name)
			}
		} else {
			err = fmt.Errorf("invalid tool/call params")
		}
	default:
		err = fmt.Errorf("method not found: %s", req.Method)
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

func (b *Bridge) getActiveEditorContext() (any, error) {
	var ctx struct {
		ActiveFilePath string   `json:"activeFilePath"`
		CursorLine     int      `json:"cursorLine"`
		CursorColumn   int      `json:"cursorColumn"`
		SelectedText   string   `json:"selectedText"`
		RecentFiles    []string `json:"recentFiles"`
	}

	buf, err := b.nvim.CurrentBuffer()
	if err != nil {
		return nil, err
	}

	name, err := b.nvim.BufferName(buf)
	if err != nil {
		return nil, err
	}
	ctx.ActiveFilePath = name

	win, err := b.nvim.CurrentWindow()
	if err != nil {
		return nil, err
	}

	pos, err := b.nvim.WindowCursor(win)
	if err != nil {
		return nil, err
	}
	ctx.CursorLine = pos[0]
	ctx.CursorColumn = pos[1]

	mode, err := b.nvim.Mode()
	if err == nil && (mode.Mode == "v" || mode.Mode == "V" || mode.Mode == "\x16") {
		var sel any
		err = b.nvim.Eval(`join(getregion(getpos("v"), getpos(".")), "\n")`, &sel)
		if err == nil {
			if s, ok := sel.(string); ok {
				ctx.SelectedText = s
			}
		}
	}

	data, _ := json.Marshal(ctx)
	return map[string]any{
		"content": []map[string]any{
			{
				"type": "text",
				"text": string(data),
			},
		},
	}, nil
}

func (b *Bridge) openFile(args json.RawMessage) (any, error) {
	var p struct {
		Path string `json:"path"`
	}
	if err := json.Unmarshal(args, &p); err != nil {
		return nil, err
	}
	err := b.nvim.Command("edit " + p.Path)
	if err != nil {
		return nil, err
	}
	return map[string]any{"content": []map[string]any{{"type": "text", "text": "OK"}}}, nil
}

func (b *Bridge) openDiff(args json.RawMessage) (any, error) {
	var p struct {
		FilePath   string `json:"filePath"`
		NewContent string `json:"newContent"`
	}
	if err := json.Unmarshal(args, &p); err != nil {
		return nil, err
	}

	_ = b.nvim.Command("edit " + p.FilePath)

	newBuf, err := b.nvim.CreateBuffer(false, true)
	if err != nil {
		return nil, err
	}

	lines := strings.Split(p.NewContent, "\n")
	byteLines := make([][]byte, len(lines))
	for i, l := range lines {
		byteLines[i] = []byte(l)
	}

	_ = b.nvim.SetBufferLines(newBuf, 0, -1, true, byteLines)
	_ = b.nvim.SetBufferOption(newBuf, "buftype", "nofile")
	_ = b.nvim.SetBufferName(newBuf, "Proposed Changes")

	_ = b.nvim.Command("tabnew")
	_ = b.nvim.SetCurrentBuffer(newBuf)
	_ = b.nvim.Command("diffthis")
	_ = b.nvim.Command("vsplit " + p.FilePath)
	_ = b.nvim.Command("diffthis")

	return map[string]any{"content": []map[string]any{{"type": "text", "text": "Diff opened in new tab"}}}, nil
}

func (b *Bridge) closeDiff(args json.RawMessage) (any, error) {
	_ = b.nvim.Command("tabclose")
	return map[string]any{"content": []map[string]any{{"type": "text", "text": "OK"}}}, nil
}

func main() {
	socketPath := flag.String("socket", "", "Path to Neovim socket")
	port := flag.Int("port", 0, "Port to listen on")
	idePidsStr := flag.String("ide-pids", "", "Space-separated candidate IDE PIDs")
	workspace := flag.String("workspace", "", "Workspace path")
	flag.Parse()

	if *socketPath == "" {
		*socketPath = os.Getenv("NVIM_SOCKET")
	}

	if *socketPath == "" {
		log.Fatal("Neovim socket path required")
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
		socketPath: *socketPath,
		port:       *port,
		authToken:  authToken,
	}

	if err := bridge.connectNvim(); err != nil {
		log.Fatalf("Failed to connect to Neovim: %v", err)
	}

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

	fmt.Printf("Bridge listening on http://localhost:%d\n", *port)

	go func() {
		for {
			if os.Getppid() == 1 {
				os.Exit(0)
			}
			time.Sleep(2 * time.Second)
		}
	}()

	log.Fatal(server.ListenAndServe())
}
