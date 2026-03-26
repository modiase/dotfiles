package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	devlogs "devlogs-lib"
)

var (
	component         string
	nvimMcpBin        = "nvim-mcp"
	tmuxNvimSelectBin = "tmux-nvim-select"
	nvrBin            = "nvr"
)

func init() {
	win := os.Getenv("TARGET_WINDOW")
	if win != "" {
		component = fmt.Sprintf("nvim-mcp(@%s)", win)
	} else {
		component = "nvim-mcp"
	}
}

func clog(level, msg string) {
	log.Printf("[devlogs] %s %s: %s", strings.ToUpper(level), component, msg)
}

type jsonRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      any             `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type jsonResponse struct {
	JSONRPC string     `json:"jsonrpc"`
	ID      any        `json:"id"`
	Result  any        `json:"result,omitempty"`
	Error   *jsonError `json:"error,omitempty"`
}

type jsonError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type connectParams struct {
	Name      string         `json:"name"`
	Arguments map[string]any `json:"arguments"`
}

type connectResult struct {
	ConnectionID string `json:"connection_id"`
}

type pendingConnect struct {
	ch chan string
}

type Proxy struct {
	socket       string
	connectionID string
	autoCounter  int
	pending      map[any]*pendingConnect
	autoIDs      map[any]bool
	toolsListIDs map[any]bool
	child        *exec.Cmd
	childStdin   *bufio.Writer
	childStdout  *bufio.Scanner
	childStderr  *bufio.Scanner
	lastHealth   string
	passthrough  []string
	mu           sync.Mutex
	outMu        sync.Mutex
	logger       *devlogs.Logger
	ctx          context.Context
	cancel       context.CancelFunc
	wg           sync.WaitGroup
}

func NewProxy(passthrough []string) *Proxy {
	ctx, cancel := context.WithCancel(context.Background())
	return &Proxy{
		pending:      make(map[any]*pendingConnect),
		autoIDs:      make(map[any]bool),
		toolsListIDs: make(map[any]bool),
		passthrough:  passthrough,
		logger:       devlogs.NewLogger("nvim-mcp"),
		ctx:          ctx,
		cancel:       cancel,
	}
}

func (p *Proxy) nextAutoID() string {
	p.mu.Lock()
	p.autoCounter++
	id := fmt.Sprintf("_auto_%d", p.autoCounter)
	p.mu.Unlock()
	return id
}

func (p *Proxy) writeChild(msg string) error {
	_, err := p.childStdin.WriteString(msg + "\n")
	if err != nil {
		return err
	}
	return p.childStdin.Flush()
}

func (p *Proxy) writeStdout(msg string) {
	p.outMu.Lock()
	defer p.outMu.Unlock()
	_, _ = fmt.Fprintln(os.Stdout, msg)
}

func (p *Proxy) errorResponse(reqID any, code int, message string) string {
	resp := jsonResponse{
		JSONRPC: "2.0",
		ID:      reqID,
		Error: &jsonError{
			Code:    code,
			Message: message,
		},
	}
	data, _ := json.Marshal(resp)
	return string(data)
}

func (p *Proxy) successResponse(reqID any, text string) string {
	resp := jsonResponse{
		JSONRPC: "2.0",
		ID:      reqID,
		Result: map[string]any{
			"content": []map[string]string{
				{"type": "text", "text": text},
			},
		},
	}
	data, _ := json.Marshal(resp)
	return string(data)
}

func extractConnectionID(result any) string {
	resultMap, ok := result.(map[string]any)
	if !ok {
		return ""
	}
	content, ok := resultMap["content"].([]any)
	if !ok {
		return ""
	}
	for _, item := range content {
		itemMap, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if itemMap["type"] != "text" {
			continue
		}
		text, ok := itemMap["text"].(string)
		if !ok {
			continue
		}
		var data connectResult
		if err := json.Unmarshal([]byte(text), &data); err == nil {
			if data.ConnectionID != "" {
				return data.ConnectionID
			}
		}
	}
	return ""
}

func (p *Proxy) discoverSocket() string {
	ctx, cancel := context.WithTimeout(p.ctx, 5*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, tmuxNvimSelectBin, "-q")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}

	for _, line := range splitLines(string(output)) {
		if len(line) > 12 && line[:12] == "NVIM_SOCKET=" {
			return line[12:]
		}
	}
	return ""
}

func splitLines(s string) []string {
	var lines []string
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] == '\n' {
			line := s[start:i]
			if len(line) > 0 && line[len(line)-1] == '\r' {
				line = line[:len(line)-1]
			}
			lines = append(lines, line)
			start = i + 1
		}
	}
	if start < len(s) {
		lines = append(lines, s[start:])
	}
	return lines
}

func (p *Proxy) sendConnect(socketPath string) string {
	reqID := p.nextAutoID()
	p.mu.Lock()
	p.autoIDs[reqID] = true
	ch := make(chan string, 1)
	p.pending[reqID] = &pendingConnect{ch: ch}
	p.socket = socketPath
	p.mu.Unlock()

	connectMsg := map[string]any{
		"jsonrpc": "2.0",
		"id":      reqID,
		"method":  "tools/call",
		"params": map[string]any{
			"name": "connect",
			"arguments": map[string]any{
				"target": socketPath,
			},
		},
	}
	data, _ := json.Marshal(connectMsg)

	p.logger.Info(fmt.Sprintf("auto-connect sending id=%s socket=%s", reqID, socketPath))
	if err := p.writeChild(string(data)); err != nil {
		p.mu.Lock()
		delete(p.pending, reqID)
		p.mu.Unlock()
		return ""
	}

	select {
	case cid := <-ch:
		return cid
	case <-time.After(5 * time.Second):
		p.logger.Warn(fmt.Sprintf("auto-connect timed out id=%s", reqID))
		p.mu.Lock()
		delete(p.pending, reqID)
		p.mu.Unlock()
		return ""
	case <-p.ctx.Done():
		return ""
	}
}

func (p *Proxy) resolvePendingConnect(msgID any, msg jsonResponse) {
	p.mu.Lock()
	pc, exists := p.pending[msgID]
	if !exists {
		p.mu.Unlock()
		return
	}
	delete(p.pending, msgID)
	p.mu.Unlock()

	if msg.Error != nil {
		p.logger.Warn(fmt.Sprintf("connect error id=%v: %s", msgID, msg.Error.Message))
		select {
		case pc.ch <- "":
		default:
		}
		return
	}

	cid := extractConnectionID(msg.Result)
	if cid != "" {
		p.mu.Lock()
		p.connectionID = cid
		p.mu.Unlock()
		p.logger.Info(fmt.Sprintf("connect response id=%v connection_id=%s", msgID, cid))
	}
	select {
	case pc.ch <- cid:
	default:
	}
}

func (p *Proxy) isFiltered(msgID any) bool {
	if msgID == nil {
		return false
	}
	p.mu.Lock()
	_, exists := p.autoIDs[msgID]
	if exists {
		delete(p.autoIDs, msgID)
	}
	p.mu.Unlock()
	return exists
}

func (p *Proxy) relayStdout() {
	defer p.wg.Done()
	for p.childStdout.Scan() {
		select {
		case <-p.ctx.Done():
			return
		default:
		}

		line := p.childStdout.Text()
		if line == "" {
			continue
		}

		var msg jsonResponse
		if err := json.Unmarshal([]byte(line), &msg); err != nil {
			p.writeStdout(line)
			continue
		}

		msgID := msg.ID

		p.mu.Lock()
		_, isPending := p.pending[msgID]
		p.mu.Unlock()

		if isPending {
			p.resolvePendingConnect(msgID, msg)
			if p.isFiltered(msgID) {
				continue
			}
		}

		if p.isFiltered(msgID) {
			continue
		}

		p.mu.Lock()
		isToolsList := p.toolsListIDs[msgID]
		if isToolsList {
			delete(p.toolsListIDs, msgID)
		}
		p.mu.Unlock()

		if isToolsList && msg.Error == nil {
			line = p.injectDiagnosticsTool(line)
		}

		p.writeStdout(line)
	}
}

func (p *Proxy) relayStderr() {
	defer p.wg.Done()
	for p.childStderr.Scan() {
		select {
		case <-p.ctx.Done():
			return
		default:
		}
		p.logger.Debug(p.childStderr.Text())
	}
}

var diagnosticsToolDef = map[string]any{
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
}

func (p *Proxy) injectDiagnosticsTool(line string) string {
	var raw map[string]any
	if err := json.Unmarshal([]byte(line), &raw); err != nil {
		return line
	}

	result, ok := raw["result"].(map[string]any)
	if !ok {
		return line
	}

	tools, ok := result["tools"].([]any)
	if !ok {
		return line
	}

	result["tools"] = append(tools, diagnosticsToolDef)
	raw["result"] = result

	data, err := json.Marshal(raw)
	if err != nil {
		return line
	}
	return string(data)
}

func (p *Proxy) handleGetDiagnostics(reqID any, args map[string]any) {
	p.mu.Lock()
	socket := p.socket
	p.mu.Unlock()

	if socket == "" || !fileExists(socket) {
		p.writeStdout(p.errorResponse(reqID, -32000, "No Neovim connection"))
		return
	}

	luaCode := `vim.json.encode(vim.tbl_map(function(d) return {file=vim.api.nvim_buf_get_name(d.bufnr), line=d.lnum+1, col=d.col+1, severity=d.severity<=1 and 'error' or 'warning', message=d.message, source=d.source or ''} end, vim.diagnostic.get(nil, {severity={min=vim.diagnostic.severity.WARN}})))`
	expr := fmt.Sprintf(`luaeval("%s")`, luaCode)

	ctx, cancel := context.WithTimeout(p.ctx, 10*time.Second)
	defer cancel()

	cmd := exec.CommandContext(ctx, nvrBin, "--servername", socket, "--remote-expr", expr)
	output, err := cmd.Output()
	if err != nil {
		p.logger.Warn(fmt.Sprintf("diagnostics failed: %v", err))
		p.writeStdout(p.errorResponse(reqID, -32000, "Failed to get diagnostics: "+err.Error()))
		return
	}

	result := strings.TrimSpace(string(output))

	if uri, ok := args["uri"].(string); ok && uri != "" {
		var diags []map[string]any
		if err := json.Unmarshal([]byte(result), &diags); err == nil {
			var filtered []map[string]any
			for _, d := range diags {
				if f, _ := d["file"].(string); f == uri {
					filtered = append(filtered, d)
				}
			}
			if filtered == nil {
				filtered = []map[string]any{}
			}
			data, _ := json.Marshal(filtered)
			result = string(data)
		}
	}

	p.writeStdout(p.successResponse(reqID, result))
}

func (p *Proxy) autoDetectLoop() {
	defer p.wg.Done()
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-p.ctx.Done():
			return
		case <-ticker.C:
			p.healthCheckAndReconnect()
		}
	}
}

func (p *Proxy) healthCheckAndReconnect() {
	p.mu.Lock()
	socket := p.socket
	lastHealth := p.lastHealth
	p.mu.Unlock()

	if socket != "" && fileExists(socket) {
		if lastHealth != "healthy" {
			p.logger.Info(fmt.Sprintf("socket healthy socket=%s", socket))
			p.mu.Lock()
			p.lastHealth = "healthy"
			p.mu.Unlock()
		}
		return
	}

	if socket != "" {
		p.logger.Info(fmt.Sprintf("socket gone socket=%s", socket))
		p.mu.Lock()
		p.socket = ""
		p.connectionID = ""
		p.lastHealth = ""
		p.mu.Unlock()
	}

	discovered := p.discoverSocket()
	if discovered == "" {
		if lastHealth != "no_socket" {
			p.logger.Info("no socket found")
		} else {
			p.logger.Debug("no socket found")
		}
		p.mu.Lock()
		p.lastHealth = "no_socket"
		p.mu.Unlock()
		return
	}

	p.logger.Info(fmt.Sprintf("discovered socket=%s", discovered))
	p.sendConnect(discovered)
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

func (p *Proxy) registerPending(reqID any) {
	p.mu.Lock()
	ch := make(chan string, 1)
	p.pending[reqID] = &pendingConnect{ch: ch}
	p.mu.Unlock()
}

func (p *Proxy) handleAutoConnect(msg jsonRequest, reqID any) {
	p.mu.Lock()
	socket := p.socket
	connID := p.connectionID
	p.mu.Unlock()

	if socket != "" && fileExists(socket) && connID != "" {
		p.logger.Info(fmt.Sprintf("connect no-op, already connected socket=%s", socket))
		result := map[string]any{
			"connection_id": connID,
			"message":       fmt.Sprintf("Already connected to %s", socket),
		}
		data, _ := json.Marshal(result)
		p.writeStdout(p.successResponse(reqID, string(data)))
		return
	}

	resolved := p.discoverSocket()
	if resolved == "" {
		p.logger.Error("connect failed, no nvim")
		p.writeStdout(p.errorResponse(reqID, -32000, "No Neovim instance found. Start Neovim in a tmux pane and try again."))
		return
	}

	p.logger.Info(fmt.Sprintf("connect resolved socket=%s", resolved))

	var params connectParams
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		p.writeStdout(p.errorResponse(reqID, -32602, "Invalid params"))
		return
	}
	if params.Arguments == nil {
		params.Arguments = make(map[string]any)
	}
	params.Arguments["target"] = resolved

	newParams := map[string]any{
		"name":      params.Name,
		"arguments": params.Arguments,
	}

	newMsg := map[string]any{
		"jsonrpc": "2.0",
		"id":      reqID,
		"method":  msg.Method,
		"params":  newParams,
	}

	p.registerPending(reqID)
	p.mu.Lock()
	p.socket = resolved
	p.mu.Unlock()

	data, _ := json.Marshal(newMsg)
	_ = p.writeChild(string(data))
}

func (p *Proxy) ensureConnected() {
	p.mu.Lock()
	connID := p.connectionID
	p.mu.Unlock()

	if connID != "" {
		return
	}

	resolved := p.discoverSocket()
	if resolved == "" {
		return
	}

	p.logger.Info(fmt.Sprintf("pre-call auto-connect socket=%s", resolved))
	p.sendConnect(resolved)
}

func (p *Proxy) handleMessage(msg jsonRequest) {
	if msg.Method == "tools/list" {
		p.mu.Lock()
		p.toolsListIDs[msg.ID] = true
		p.mu.Unlock()
		data, _ := json.Marshal(msg)
		_ = p.writeChild(string(data))
		return
	}

	if msg.Method != "tools/call" {
		data, _ := json.Marshal(msg)
		_ = p.writeChild(string(data))
		return
	}

	var params connectParams
	if err := json.Unmarshal(msg.Params, &params); err != nil {
		data, _ := json.Marshal(msg)
		_ = p.writeChild(string(data))
		return
	}

	reqID := msg.ID

	if params.Name == "connect" || params.Name == "connect_tcp" {
		target, _ := params.Arguments["target"].(string)
		if target == "" || target == "auto" {
			p.handleAutoConnect(msg, reqID)
			return
		}
		p.registerPending(reqID)
		data, _ := json.Marshal(msg)
		_ = p.writeChild(string(data))
		return
	}

	if params.Name == "get_diagnostics" {
		go p.handleGetDiagnostics(reqID, params.Arguments)
		return
	}

	p.ensureConnected()

	p.mu.Lock()
	connID := p.connectionID
	p.mu.Unlock()

	if connID != "" {
		if _, exists := params.Arguments["connection_id"]; exists {
			params.Arguments["connection_id"] = connID
			newParams := map[string]any{
				"name":      params.Name,
				"arguments": params.Arguments,
			}
			newMsg := map[string]any{
				"jsonrpc": "2.0",
				"id":      reqID,
				"method":  msg.Method,
				"params":  newParams,
			}
			data, _ := json.Marshal(newMsg)
			_ = p.writeChild(string(data))
			return
		}
	}

	data, _ := json.Marshal(msg)
	_ = p.writeChild(string(data))
}

func (p *Proxy) relayStdin() {
	scanner := bufio.NewScanner(os.Stdin)
	for scanner.Scan() {
		select {
		case <-p.ctx.Done():
			return
		default:
		}

		line := scanner.Text()
		if line == "" {
			continue
		}

		var msg jsonRequest
		if err := json.Unmarshal([]byte(line), &msg); err != nil {
			_ = p.writeChild(line)
			continue
		}

		p.handleMessage(msg)
	}
}

func (p *Proxy) run() int {
	defer func() {
		if r := recover(); r != nil {
			clog("error", fmt.Sprintf("panic: %v", r))
			panic(r)
		}
	}()

	socketPath := p.discoverSocket()

	args := []string{nvimMcpBin}
	if socketPath != "" {
		args = append(args, "--connect", socketPath)
		p.mu.Lock()
		p.socket = socketPath
		p.mu.Unlock()
		p.logger.Info(fmt.Sprintf("socket discovered socket=%s", socketPath))
	} else {
		p.logger.Info("no socket discovered")
	}
	args = append(args, p.passthrough...)

	p.child = exec.CommandContext(p.ctx, args[0], args[1:]...)

	stdin, err := p.child.StdinPipe()
	if err != nil {
		p.logger.Error("failed to create stdin pipe: " + err.Error())
		return 1
	}
	p.childStdin = bufio.NewWriter(stdin)

	stdout, err := p.child.StdoutPipe()
	if err != nil {
		p.logger.Error("failed to create stdout pipe: " + err.Error())
		return 1
	}
	p.childStdout = bufio.NewScanner(stdout)

	stderr, err := p.child.StderrPipe()
	if err != nil {
		p.logger.Error("failed to create stderr pipe: " + err.Error())
		return 1
	}
	p.childStderr = bufio.NewScanner(stderr)

	if err := p.child.Start(); err != nil {
		p.logger.Error("failed to start nvim-mcp: " + err.Error())
		return 1
	}

	p.wg.Add(3)
	go p.relayStdout()
	go p.relayStderr()
	go p.autoDetectLoop()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		<-sigCh
		p.cancel()
	}()

	p.relayStdin()

	p.cancel()

	_ = p.child.Process.Signal(os.Interrupt)
	done := make(chan error, 1)
	go func() { done <- p.child.Wait() }()

	select {
	case <-time.After(5 * time.Second):
		_ = p.child.Process.Kill()
		<-done
	case err := <-done:
		if err != nil {
			p.logger.Error("child wait error: " + err.Error())
		}
	}

	p.wg.Wait()

	if p.child.ProcessState != nil {
		return p.child.ProcessState.ExitCode()
	}
	return 0
}

func parsePassthroughArgs() []string {
	args := os.Args[1:]
	var filtered []string
	skipNext := false
	for _, arg := range args {
		if skipNext {
			skipNext = false
			continue
		}
		if len(arg) >= 13 && arg[:12] == "--wrapper-id" {
			if arg[12] == '=' {
				continue
			}
			if arg == "--wrapper-id" {
				skipNext = true
				continue
			}
		}
		filtered = append(filtered, arg)
	}
	return filtered
}

func main() {
	_ = flag.String("wrapper-id", "", "Wrapper instance identifier")
	flag.Parse()

	proxy := NewProxy(parsePassthroughArgs())
	os.Exit(proxy.run())
}
