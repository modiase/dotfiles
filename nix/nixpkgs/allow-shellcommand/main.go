package main

import (
	"bytes"
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	devlogs "devlogs-lib"
	"mvdan.cc/sh/v3/syntax"
)

// gitCommonDirFn / getwdFn are seams for tests; production code calls
// gitCommonDir / os.Getwd directly.
var (
	gitCommonDirFn                        = gitCommonDir
	getwdFn        func() (string, error) = os.Getwd
)

func gitCommonDir(path string) (string, bool) {
	out, err := exec.Command("git", "-C", path, "rev-parse", "--git-common-dir").Output()
	if err != nil {
		return "", false
	}
	dir := strings.TrimSpace(string(out))
	if dir == "" {
		return "", false
	}
	if !filepath.IsAbs(dir) {
		dir = filepath.Join(path, dir)
	}
	abs, err := filepath.Abs(dir)
	if err != nil {
		return "", false
	}
	return filepath.Clean(abs), true
}

//go:embed deny-rules.json
var embeddedDenyRulesJSON []byte

type Decision struct {
	Action string `json:"permissionDecision,omitempty"`
	Reason string `json:"permissionDecisionReason,omitempty"`
	Retry  bool   `json:"retry,omitempty"`
}

func allow() *Decision             { return &Decision{Action: "allow"} }
func deny(reason string) *Decision { return &Decision{Action: "deny", Reason: reason, Retry: true} }
func abstain() *Decision           { return nil }

type hookInput struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

type commandInfo struct {
	Command    string
	Captured   bool
	AssignOnly bool
}

const assignOnlySentinel = "<assign-only>"

type denyRule struct {
	Pattern      string
	Reason       string
	TopLevelOnly bool
}

type embeddedDenyRule struct {
	Rule         string `json:"rule"`
	Reason       string `json:"reason"`
	TopLevelOnly bool   `json:"topLevelOnly"`
}

type settingsFile struct {
	Permissions struct {
		Allow []string `json:"allow"`
		Deny  []string `json:"deny"`
	} `json:"permissions"`
}

func bashPattern(entry string) (string, bool) {
	if !strings.HasPrefix(entry, "Bash(") || !strings.HasSuffix(entry, ")") {
		return "", false
	}
	p := entry[5 : len(entry)-1]
	p = strings.ReplaceAll(p, ":*", "*")
	return p, true
}

func extractAllowPatterns(settings *settingsFile) []string {
	var patterns []string
	for _, entry := range settings.Permissions.Allow {
		if p, ok := bashPattern(entry); ok {
			patterns = append(patterns, p)
		}
	}
	return patterns
}

func loadEmbeddedDenyRules() []denyRule {
	var embedded []embeddedDenyRule
	if err := json.Unmarshal(embeddedDenyRulesJSON, &embedded); err != nil {
		return nil
	}
	rules := make([]denyRule, 0, len(embedded))
	for _, e := range embedded {
		if p, ok := bashPattern(e.Rule); ok {
			reason := e.Reason
			if reason == "" {
				reason = "Command denied by policy."
			}
			rules = append(rules, denyRule{Pattern: p, Reason: reason, TopLevelOnly: e.TopLevelOnly})
		}
	}
	return rules
}

func extractDenyRules(settings *settingsFile) []denyRule {
	var rules []denyRule
	for _, entry := range settings.Permissions.Deny {
		if p, ok := bashPattern(entry); ok {
			rules = append(rules, denyRule{Pattern: p, Reason: "Command denied by policy."})
		}
	}
	return rules
}

func globMatch(pattern, s string) bool {
	parts := strings.Split(pattern, "*")
	if len(parts) == 1 {
		return pattern == s
	}
	if !strings.HasPrefix(s, parts[0]) {
		return false
	}
	s = s[len(parts[0]):]
	for _, part := range parts[1 : len(parts)-1] {
		idx := strings.Index(s, part)
		if idx < 0 {
			return false
		}
		s = s[idx+len(part):]
	}
	return strings.HasSuffix(s, parts[len(parts)-1])
}

func loadSettings() (*settingsFile, error) {
	configDir := os.Getenv("CLAUDE_CONFIG_DIR")
	if configDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		configDir = filepath.Join(home, ".claude")
	}
	data, err := os.ReadFile(filepath.Join(configDir, "settings.json"))
	if err != nil {
		return nil, err
	}
	var s settingsFile
	if err := json.Unmarshal(data, &s); err != nil {
		return nil, err
	}
	return &s, nil
}

func firstSeparator(s string) (idx int, sep string) {
	seps := []string{"&&", ";", "||"}
	best := -1
	bestSep := ""
	for _, sep := range seps {
		if i := strings.Index(s, sep); i >= 0 && (best < 0 || i < best) {
			best = i
			bestSep = sep
		}
	}
	return best, bestSep
}

func hasShellMeta(s string) bool {
	return strings.ContainsAny(s, "~$`()&;|")
}

func printWord(printer *syntax.Printer, word *syntax.Word) string {
	var buf bytes.Buffer
	_ = printer.Print(&buf, word)
	return buf.String()
}

func printNode(printer *syntax.Printer, node syntax.Node) string {
	var buf bytes.Buffer
	_ = printer.Print(&buf, node)
	return buf.String()
}

// stripBackslashEscapes removes unquoted backslash escapes from a Lit value,
// matching how bash interprets them (e.g. r\m -> rm).
func stripBackslashEscapes(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// resolveWord attempts to reduce a word to its literal string value by walking
// all parts and concatenating. Returns the printed form if any part contains
// an expansion that cannot be statically resolved.
func resolveWord(word *syntax.Word, printed string) string {
	var b strings.Builder
	for _, part := range word.Parts {
		switch p := part.(type) {
		case *syntax.Lit:
			b.WriteString(stripBackslashEscapes(p.Value))
		case *syntax.SglQuoted:
			if p.Dollar {
				return printed
			}
			b.WriteString(p.Value)
		case *syntax.DblQuoted:
			for _, dp := range p.Parts {
				if lit, ok := dp.(*syntax.Lit); ok {
					b.WriteString(stripBackslashEscapes(lit.Value))
				} else {
					return printed
				}
			}
		default:
			return printed
		}
	}
	return b.String()
}

// printCallExpr returns one or two command strings for a CallExpr.
// When assigns are present (e.g. FOO=bar rm -rf /), it returns both the full
// form ("FOO=bar rm -rf /") and the args-only form ("rm -rf /"). The full form
// prevents false allows (PATH=/evil git status won't match "git*"), while the
// args-only form ensures deny rules still catch the underlying command.
func printCallExpr(call *syntax.CallExpr) []string {
	printer := syntax.NewPrinter()
	argParts := make([]string, 0, len(call.Args))
	for _, word := range call.Args {
		printed := printWord(printer, word)
		argParts = append(argParts, resolveWord(word, printed))
	}
	argsOnly := strings.Join(argParts, " ")

	if len(call.Assigns) == 0 {
		return []string{argsOnly}
	}

	assignParts := make([]string, 0, len(call.Assigns))
	for _, assign := range call.Assigns {
		assignParts = append(assignParts, printNode(printer, assign))
	}
	full := strings.Join(assignParts, " ") + " " + argsOnly
	return []string{full, argsOnly}
}

func canResolveWord(word *syntax.Word) bool {
	for _, part := range word.Parts {
		switch p := part.(type) {
		case *syntax.Lit:
		case *syntax.SglQuoted:
			if p.Dollar {
				return false
			}
		case *syntax.DblQuoted:
			for _, dp := range p.Parts {
				if _, ok := dp.(*syntax.Lit); !ok {
					return false
				}
			}
		default:
			return false
		}
	}
	return true
}

func shellQuote(s string) string {
	if s == "" || strings.ContainsAny(s, " \t\n'\"\\$`|&;(){}[]!?*~#<>") {
		return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
	}
	return s
}

var sshFlagsWithArg = map[byte]bool{
	'b': true, 'c': true, 'D': true, 'E': true, 'e': true,
	'F': true, 'I': true, 'i': true, 'J': true, 'L': true,
	'l': true, 'm': true, 'O': true, 'o': true, 'p': true,
	'Q': true, 'R': true, 'S': true, 'W': true, 'w': true,
}

func extractSSHRemoteCmd(args []*syntax.Word) (string, bool) {
	printer := syntax.NewPrinter()
	resolved := make([]string, len(args))
	for i, w := range args {
		if !canResolveWord(w) {
			return "", false
		}
		resolved[i] = resolveWord(w, printWord(printer, w))
	}

	i := 0
	for i < len(resolved) {
		arg := resolved[i]
		if arg == "--" {
			i++
			break
		}
		if !strings.HasPrefix(arg, "-") || len(arg) == 1 {
			break
		}
		flagStr := arg[1:]
		consumeNext := false
		for k := 0; k < len(flagStr); k++ {
			if sshFlagsWithArg[flagStr[k]] {
				if k+1 < len(flagStr) {
					break
				}
				consumeNext = true
				break
			}
		}
		i++
		if consumeNext && i < len(resolved) {
			i++
		}
	}

	if i >= len(resolved) {
		return "", true
	}
	i++
	if i >= len(resolved) {
		return "", true
	}
	return strings.Join(resolved[i:], " "), true
}

func extractShellExecCmd(args []*syntax.Word) (string, bool) {
	printer := syntax.NewPrinter()
	for i := 0; i < len(args); i++ {
		if !canResolveWord(args[i]) {
			return "", false
		}
		arg := resolveWord(args[i], printWord(printer, args[i]))
		if !strings.HasPrefix(arg, "-") || len(arg) == 1 {
			continue
		}
		flagStr := arg[1:]
		skipNext := false
		for k := 0; k < len(flagStr); k++ {
			ch := flagStr[k]
			if ch == 'c' {
				if k+1 < len(flagStr) {
					return flagStr[k+1:], true
				}
				i++
				if i >= len(args) {
					return "", true
				}
				if !canResolveWord(args[i]) {
					return "", false
				}
				return resolveWord(args[i], printWord(printer, args[i])), true
			}
			if ch == 'o' {
				if k+1 < len(flagStr) {
					break
				}
				skipNext = true
				break
			}
		}
		if skipNext {
			i++
		}
	}
	return "", true
}

func extractNixShellCmd(args []*syntax.Word) (string, bool) {
	printer := syntax.NewPrinter()
	for i := 0; i < len(args); i++ {
		if !canResolveWord(args[i]) {
			return "", false
		}
		arg := resolveWord(args[i], printWord(printer, args[i]))
		if arg == "--run" || arg == "--command" {
			i++
			if i >= len(args) {
				return "", true
			}
			if !canResolveWord(args[i]) {
				return "", false
			}
			return resolveWord(args[i], printWord(printer, args[i])), true
		}
	}
	return "", true
}

func extractNixCmd(args []*syntax.Word) (string, bool) {
	if len(args) == 0 {
		return "", true
	}
	printer := syntax.NewPrinter()
	if !canResolveWord(args[0]) {
		return "", false
	}
	subcmd := resolveWord(args[0], printWord(printer, args[0]))
	if subcmd != "develop" && subcmd != "shell" {
		return "", true
	}
	for i := 1; i < len(args); i++ {
		if !canResolveWord(args[i]) {
			return "", false
		}
		arg := resolveWord(args[i], printWord(printer, args[i]))
		if arg == "--command" {
			remaining := args[i+1:]
			if len(remaining) == 0 {
				return "", true
			}
			parts := make([]string, len(remaining))
			for j, w := range remaining {
				if !canResolveWord(w) {
					return "", false
				}
				parts[j] = shellQuote(resolveWord(w, printWord(printer, w)))
			}
			return strings.Join(parts, " "), true
		}
	}
	return "", true
}

var transparentWrappers = map[string]func([]*syntax.Word) (string, bool){
	"ssh":       extractSSHRemoteCmd,
	"bash":      extractShellExecCmd,
	"sh":        extractShellExecCmd,
	"zsh":       extractShellExecCmd,
	"nix-shell": extractNixShellCmd,
	"nix":       extractNixCmd,
}

func unwrapTransparentWrapper(call *syntax.CallExpr) []commandInfo {
	if len(call.Args) == 0 || len(call.Assigns) > 0 {
		return nil
	}
	printer := syntax.NewPrinter()
	name := resolveWord(call.Args[0], printWord(printer, call.Args[0]))
	extractFn, ok := transparentWrappers[name]
	if !ok {
		return nil
	}
	innerCmd, canResolve := extractFn(call.Args[1:])
	if !canResolve || innerCmd == "" {
		return nil
	}
	cmds, err := extractCommands(innerCmd)
	if err != nil {
		return nil
	}
	return cmds
}

func extractCommands(cmd string) ([]commandInfo, error) {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	reader := strings.NewReader(cmd)
	file, err := parser.Parse(reader, "")
	if err != nil {
		return nil, err
	}

	var commands []commandInfo
	var walkStmts func(stmts []*syntax.Stmt, captured bool)
	var walkStmt func(stmt *syntax.Stmt, captured bool)
	var walkCmd func(cmd syntax.Command, captured bool)
	var walkWords func(words []*syntax.Word, captured bool)
	var walkWordParts func(parts []syntax.WordPart, captured bool)

	walkWordParts = func(parts []syntax.WordPart, captured bool) {
		for _, part := range parts {
			switch p := part.(type) {
			case *syntax.CmdSubst:
				walkStmts(p.Stmts, true)
			case *syntax.ProcSubst:
				walkStmts(p.Stmts, true)
			case *syntax.DblQuoted:
				walkWordParts(p.Parts, captured)
			case *syntax.ParamExp:
				if p.Index != nil {
					walkArithm(p.Index, &commands, captured, walkStmts, walkWordParts)
				}
				if p.Slice != nil {
					if p.Slice.Offset != nil {
						walkArithm(p.Slice.Offset, &commands, captured, walkStmts, walkWordParts)
					}
					if p.Slice.Length != nil {
						walkArithm(p.Slice.Length, &commands, captured, walkStmts, walkWordParts)
					}
				}
				if p.Repl != nil {
					if p.Repl.Orig != nil {
						walkWordParts(p.Repl.Orig.Parts, captured)
					}
					if p.Repl.With != nil {
						walkWordParts(p.Repl.With.Parts, captured)
					}
				}
				if p.Exp != nil && p.Exp.Word != nil {
					walkWordParts(p.Exp.Word.Parts, captured)
				}
			case *syntax.ArithmExp:
				if p.X != nil {
					walkArithm(p.X, &commands, captured, walkStmts, walkWordParts)
				}
			}
		}
	}

	walkWords = func(words []*syntax.Word, captured bool) {
		for _, word := range words {
			walkWordParts(word.Parts, captured)
		}
	}

	walkAssigns := func(assigns []*syntax.Assign, captured bool) {
		for _, assign := range assigns {
			if assign.Index != nil {
				walkArithm(assign.Index, &commands, captured, walkStmts, walkWordParts)
			}
			if assign.Value != nil {
				walkWordParts(assign.Value.Parts, captured)
			}
			if assign.Array != nil {
				for _, elem := range assign.Array.Elems {
					if elem.Index != nil {
						walkArithm(elem.Index, &commands, captured, walkStmts, walkWordParts)
					}
					if elem.Value != nil {
						walkWordParts(elem.Value.Parts, captured)
					}
				}
			}
		}
	}

	walkStmt = func(stmt *syntax.Stmt, captured bool) {
		if stmt == nil {
			return
		}
		for _, redir := range stmt.Redirs {
			if redir.Word != nil {
				walkWordParts(redir.Word.Parts, captured)
			}
			if redir.Hdoc != nil {
				walkWordParts(redir.Hdoc.Parts, captured)
			}
		}
		if stmt.Cmd != nil {
			walkCmd(stmt.Cmd, captured)
		}
	}

	walkStmts = func(stmts []*syntax.Stmt, captured bool) {
		for _, stmt := range stmts {
			walkStmt(stmt, captured)
		}
	}

	walkCmd = func(cmd syntax.Command, captured bool) {
		switch c := cmd.(type) {
		case *syntax.CallExpr:
			walkAssigns(c.Assigns, captured)
			walkWords(c.Args, captured)
			if inner := unwrapTransparentWrapper(c); inner != nil {
				for _, ic := range inner {
					commands = append(commands, commandInfo{
						Command:  ic.Command,
						Captured: captured || ic.Captured,
					})
				}
			} else if len(c.Args) > 0 {
				for _, s := range printCallExpr(c) {
					commands = append(commands, commandInfo{Command: s, Captured: captured})
				}
			} else if len(c.Assigns) > 0 {
				// Pure variable assignment (e.g. `FOO=bar`). Sets a shell
				// variable but does not run any external command, so it is
				// safe to allow. Emit a sentinel so run() knows the script
				// was understood; the per-command loop skips AssignOnly
				// entries when checking allow patterns.
				commands = append(commands, commandInfo{
					Command:    assignOnlySentinel,
					Captured:   captured,
					AssignOnly: true,
				})
			}
		case *syntax.BinaryCmd:
			if c.Op == syntax.Pipe || c.Op == syntax.PipeAll {
				walkStmt(c.X, true)
				walkStmt(c.Y, captured)
			} else {
				walkStmt(c.X, captured)
				walkStmt(c.Y, captured)
			}
		case *syntax.Subshell:
			walkStmts(c.Stmts, captured)
		case *syntax.Block:
			walkStmts(c.Stmts, captured)
		case *syntax.IfClause:
			walkStmts(c.Cond, captured)
			walkStmts(c.Then, captured)
			if c.Else != nil {
				walkCmd(c.Else, captured)
			}
		case *syntax.WhileClause:
			walkStmts(c.Cond, captured)
			walkStmts(c.Do, captured)
		case *syntax.ForClause:
			switch loop := c.Loop.(type) {
			case *syntax.WordIter:
				walkWords(loop.Items, captured)
			case *syntax.CStyleLoop:
				if loop.Init != nil {
					walkArithm(loop.Init, &commands, captured, walkStmts, walkWordParts)
				}
				if loop.Cond != nil {
					walkArithm(loop.Cond, &commands, captured, walkStmts, walkWordParts)
				}
				if loop.Post != nil {
					walkArithm(loop.Post, &commands, captured, walkStmts, walkWordParts)
				}
			}
			walkStmts(c.Do, captured)
		case *syntax.CaseClause:
			if c.Word != nil {
				walkWordParts(c.Word.Parts, captured)
			}
			for _, item := range c.Items {
				walkWords(item.Patterns, captured)
				walkStmts(item.Stmts, captured)
			}
		case *syntax.FuncDecl:
			walkStmt(c.Body, captured)
		case *syntax.TestDecl:
			if c.Description != nil {
				walkWordParts(c.Description.Parts, captured)
			}
			walkStmt(c.Body, captured)
		case *syntax.DeclClause:
			walkAssigns(c.Args, captured)
		case *syntax.TimeClause:
			walkStmt(c.Stmt, captured)
		case *syntax.CoprocClause:
			walkStmt(c.Stmt, captured)
		case *syntax.ArithmCmd:
			if c.X != nil {
				walkArithm(c.X, &commands, captured, walkStmts, walkWordParts)
			}
		case *syntax.TestClause:
			walkTestExpr(c.X, &commands, captured, walkStmts, walkWordParts)
		case *syntax.LetClause:
			for _, expr := range c.Exprs {
				walkArithm(expr, &commands, captured, walkStmts, walkWordParts)
			}
		}
	}

	walkStmts(file.Stmts, false)
	return commands, nil
}

func walkArithm(expr syntax.ArithmExpr, commands *[]commandInfo, captured bool, walkStmts func([]*syntax.Stmt, bool), walkWordParts func([]syntax.WordPart, bool)) {
	switch e := expr.(type) {
	case *syntax.Word:
		walkWordParts(e.Parts, captured)
	case *syntax.BinaryArithm:
		walkArithm(e.X, commands, captured, walkStmts, walkWordParts)
		walkArithm(e.Y, commands, captured, walkStmts, walkWordParts)
	case *syntax.UnaryArithm:
		walkArithm(e.X, commands, captured, walkStmts, walkWordParts)
	case *syntax.ParenArithm:
		walkArithm(e.X, commands, captured, walkStmts, walkWordParts)
	}
}

func walkTestExpr(expr syntax.TestExpr, commands *[]commandInfo, captured bool, walkStmts func([]*syntax.Stmt, bool), walkWordParts func([]syntax.WordPart, bool)) {
	switch e := expr.(type) {
	case *syntax.Word:
		walkWordParts(e.Parts, captured)
	case *syntax.BinaryTest:
		walkTestExpr(e.X, commands, captured, walkStmts, walkWordParts)
		walkTestExpr(e.Y, commands, captured, walkStmts, walkWordParts)
	case *syntax.UnaryTest:
		walkTestExpr(e.X, commands, captured, walkStmts, walkWordParts)
	case *syntax.ParenTest:
		walkTestExpr(e.X, commands, captured, walkStmts, walkWordParts)
	}
}

func stripCdPrefix(cmd string, log *devlogs.Logger) (string, *Decision) {
	if !strings.HasPrefix(cmd, "cd ") {
		return cmd, nil
	}

	rest := cmd[3:]
	var cdPath, remaining string
	if idx, sep := firstSeparator(rest); idx >= 0 {
		cdPath = strings.TrimSpace(rest[:idx])
		remaining = strings.TrimSpace(rest[idx+len(sep):])
	} else {
		cdPath = strings.TrimSpace(rest)
		remaining = ""
	}

	if len(cdPath) >= 2 {
		if (cdPath[0] == '"' && cdPath[len(cdPath)-1] == '"') ||
			(cdPath[0] == '\'' && cdPath[len(cdPath)-1] == '\'') {
			cdPath = cdPath[1 : len(cdPath)-1]
		}
	}

	if cdPath == "" || hasShellMeta(cdPath) {
		log.Info("cd path empty or contains shell metacharacters, abstaining: " + cdPath)
		return cmd, nil
	}

	resolved, err := filepath.Abs(cdPath)
	if err != nil {
		log.Debug("cannot resolve cd path: " + err.Error())
		return cmd, nil
	}
	resolved = filepath.Clean(resolved)

	cwd, err := getwdFn()
	if err != nil {
		log.Debug("cannot get cwd: " + err.Error())
		return cmd, nil
	}
	cwd = filepath.Clean(cwd)

	if resolved != cwd && !strings.HasPrefix(resolved, cwd+string(filepath.Separator)) {
		cwdRepo, cwdOK := gitCommonDirFn(cwd)
		targetRepo, targetOK := gitCommonDirFn(resolved)
		if !cwdOK || !targetOK || cwdRepo != targetRepo {
			log.Info("cd target outside cwd, abstaining: " + resolved)
			return cmd, nil
		}
		log.Debug("cd target shares git common-dir with cwd, allowing: " + resolved)
	}

	if remaining == "" {
		log.Info("bare cd within cwd, allowing: " + resolved)
		return "", allow()
	}

	log.Debug("stripped safe cd prefix, evaluating: " + remaining)
	return remaining, nil
}

func run(log *devlogs.Logger) *Decision {
	data, err := io.ReadAll(os.Stdin)
	if err != nil {
		log.Error("failed to read stdin: " + err.Error())
		return abstain()
	}

	var input hookInput
	if err := json.Unmarshal(data, &input); err != nil {
		log.Error("failed to parse input: " + err.Error())
		return abstain()
	}

	cmd := input.ToolInput.Command
	if cmd == "" {
		return abstain()
	}

	log.Debug("checking cmd=" + cmd)

	remaining, cdDecision := stripCdPrefix(cmd, log)
	if cdDecision != nil {
		return cdDecision
	}
	if remaining == "" {
		return abstain()
	}

	settings, err := loadSettings()
	if err != nil {
		log.Debug("no settings: " + err.Error())
		return abstain()
	}

	commands, err := extractCommands(remaining)
	if err != nil {
		log.Debug("parse failed, abstaining: " + err.Error())
		return abstain()
	}

	denyRules := loadEmbeddedDenyRules()
	denyRules = append(denyRules, extractDenyRules(settings)...)
	allowPatterns := extractAllowPatterns(settings)

	allAllowed := true
	for _, ci := range commands {
		if ci.AssignOnly {
			continue
		}
		for _, rule := range denyRules {
			if rule.TopLevelOnly && ci.Captured {
				continue
			}
			if globMatch(rule.Pattern, ci.Command) {
				log.Info("denied cmd=" + ci.Command)
				return deny(rule.Reason)
			}
		}

		matched := false
		for _, pattern := range allowPatterns {
			if globMatch(pattern, ci.Command) {
				matched = true
				break
			}
		}
		if !matched {
			allAllowed = false
		}
	}

	if allAllowed && len(commands) > 0 {
		log.Info("allowed all commands in: " + remaining)
		return allow()
	}

	return abstain()
}

func main() {
	_ = flag.String("wrapper-id", "", "Wrapper instance identifier")
	flag.Parse()
	log := devlogs.NewLogger("allow-shellcommand")
	decision := run(log)
	if decision != nil {
		out, _ := json.Marshal(decision)
		fmt.Println(string(out))
	}
}
