package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	devlogs "devlogs-lib"
	"mvdan.cc/sh/v3/syntax"
)

type Decision struct {
	Action string `json:"permissionDecision,omitempty"`
	Reason string `json:"permissionDecisionReason,omitempty"`
}

func allow() *Decision             { return &Decision{Action: "allow"} }
func deny(reason string) *Decision { return &Decision{Action: "deny", Reason: reason} }
func abstain() *Decision           { return nil }

type hookInput struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

type denyRule struct {
	Pattern string
	Reason  string
}

type settingsFile struct {
	Permissions struct {
		Allow   []string          `json:"allow"`
		DenyRaw []json.RawMessage `json:"deny"`
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

func extractDenyRules(settings *settingsFile) []denyRule {
	var rules []denyRule
	for _, raw := range settings.Permissions.DenyRaw {
		var str string
		if err := json.Unmarshal(raw, &str); err == nil {
			if p, ok := bashPattern(str); ok {
				rules = append(rules, denyRule{Pattern: p, Reason: "Command denied by policy."})
			}
			continue
		}
		var obj struct {
			Rule   string `json:"rule"`
			Reason string `json:"reason"`
		}
		if err := json.Unmarshal(raw, &obj); err == nil && obj.Rule != "" {
			if p, ok := bashPattern(obj.Rule); ok {
				reason := obj.Reason
				if reason == "" {
					reason = "Command denied by policy."
				}
				rules = append(rules, denyRule{Pattern: p, Reason: reason})
			}
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

func extractCommands(cmd string) ([]string, error) {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	reader := strings.NewReader(cmd)
	file, err := parser.Parse(reader, "")
	if err != nil {
		return nil, err
	}

	var commands []string
	var walkStmts func(stmts []*syntax.Stmt)
	var walkCmd func(cmd syntax.Command)
	var walkWords func(words []*syntax.Word)
	var walkWordParts func(parts []syntax.WordPart)

	walkWordParts = func(parts []syntax.WordPart) {
		for _, part := range parts {
			switch p := part.(type) {
			case *syntax.CmdSubst:
				walkStmts(p.Stmts)
			case *syntax.ProcSubst:
				walkStmts(p.Stmts)
			case *syntax.DblQuoted:
				walkWordParts(p.Parts)
			case *syntax.ParamExp:
				if p.Index != nil {
					walkArithm(p.Index, &commands, walkStmts, walkWordParts)
				}
				if p.Slice != nil {
					if p.Slice.Offset != nil {
						walkArithm(p.Slice.Offset, &commands, walkStmts, walkWordParts)
					}
					if p.Slice.Length != nil {
						walkArithm(p.Slice.Length, &commands, walkStmts, walkWordParts)
					}
				}
				if p.Repl != nil {
					if p.Repl.Orig != nil {
						walkWordParts(p.Repl.Orig.Parts)
					}
					if p.Repl.With != nil {
						walkWordParts(p.Repl.With.Parts)
					}
				}
				if p.Exp != nil && p.Exp.Word != nil {
					walkWordParts(p.Exp.Word.Parts)
				}
			case *syntax.ArithmExp:
				if p.X != nil {
					walkArithm(p.X, &commands, walkStmts, walkWordParts)
				}
			}
		}
	}

	walkWords = func(words []*syntax.Word) {
		for _, word := range words {
			walkWordParts(word.Parts)
		}
	}

	walkAssigns := func(assigns []*syntax.Assign) {
		for _, assign := range assigns {
			if assign.Index != nil {
				walkArithm(assign.Index, &commands, walkStmts, walkWordParts)
			}
			if assign.Value != nil {
				walkWordParts(assign.Value.Parts)
			}
			if assign.Array != nil {
				for _, elem := range assign.Array.Elems {
					if elem.Index != nil {
						walkArithm(elem.Index, &commands, walkStmts, walkWordParts)
					}
					if elem.Value != nil {
						walkWordParts(elem.Value.Parts)
					}
				}
			}
		}
	}

	walkStmt := func(stmt *syntax.Stmt) {
		if stmt == nil {
			return
		}
		for _, redir := range stmt.Redirs {
			if redir.Word != nil {
				walkWordParts(redir.Word.Parts)
			}
			if redir.Hdoc != nil {
				walkWordParts(redir.Hdoc.Parts)
			}
		}
		if stmt.Cmd != nil {
			walkCmd(stmt.Cmd)
		}
	}

	walkStmts = func(stmts []*syntax.Stmt) {
		for _, stmt := range stmts {
			walkStmt(stmt)
		}
	}

	walkCmd = func(cmd syntax.Command) {
		switch c := cmd.(type) {
		case *syntax.CallExpr:
			walkAssigns(c.Assigns)
			walkWords(c.Args)
			if len(c.Args) > 0 {
				commands = append(commands, printCallExpr(c)...)
			}
		case *syntax.BinaryCmd:
			walkStmt(c.X)
			walkStmt(c.Y)
		case *syntax.Subshell:
			walkStmts(c.Stmts)
		case *syntax.Block:
			walkStmts(c.Stmts)
		case *syntax.IfClause:
			walkStmts(c.Cond)
			walkStmts(c.Then)
			if c.Else != nil {
				walkCmd(c.Else)
			}
		case *syntax.WhileClause:
			walkStmts(c.Cond)
			walkStmts(c.Do)
		case *syntax.ForClause:
			switch loop := c.Loop.(type) {
			case *syntax.WordIter:
				walkWords(loop.Items)
			case *syntax.CStyleLoop:
				if loop.Init != nil {
					walkArithm(loop.Init, &commands, walkStmts, walkWordParts)
				}
				if loop.Cond != nil {
					walkArithm(loop.Cond, &commands, walkStmts, walkWordParts)
				}
				if loop.Post != nil {
					walkArithm(loop.Post, &commands, walkStmts, walkWordParts)
				}
			}
			walkStmts(c.Do)
		case *syntax.CaseClause:
			if c.Word != nil {
				walkWordParts(c.Word.Parts)
			}
			for _, item := range c.Items {
				walkWords(item.Patterns)
				walkStmts(item.Stmts)
			}
		case *syntax.FuncDecl:
			walkStmt(c.Body)
		case *syntax.TestDecl:
			if c.Description != nil {
				walkWordParts(c.Description.Parts)
			}
			walkStmt(c.Body)
		case *syntax.DeclClause:
			walkAssigns(c.Args)
		case *syntax.TimeClause:
			walkStmt(c.Stmt)
		case *syntax.CoprocClause:
			walkStmt(c.Stmt)
		case *syntax.ArithmCmd:
			if c.X != nil {
				walkArithm(c.X, &commands, walkStmts, walkWordParts)
			}
		case *syntax.TestClause:
			walkTestExpr(c.X, &commands, walkStmts, walkWordParts)
		case *syntax.LetClause:
			for _, expr := range c.Exprs {
				walkArithm(expr, &commands, walkStmts, walkWordParts)
			}
		}
	}

	walkStmts(file.Stmts)
	return commands, nil
}

func walkArithm(expr syntax.ArithmExpr, commands *[]string, walkStmts func([]*syntax.Stmt), walkWordParts func([]syntax.WordPart)) {
	switch e := expr.(type) {
	case *syntax.Word:
		walkWordParts(e.Parts)
	case *syntax.BinaryArithm:
		walkArithm(e.X, commands, walkStmts, walkWordParts)
		walkArithm(e.Y, commands, walkStmts, walkWordParts)
	case *syntax.UnaryArithm:
		walkArithm(e.X, commands, walkStmts, walkWordParts)
	case *syntax.ParenArithm:
		walkArithm(e.X, commands, walkStmts, walkWordParts)
	}
}

func walkTestExpr(expr syntax.TestExpr, commands *[]string, walkStmts func([]*syntax.Stmt), walkWordParts func([]syntax.WordPart)) {
	switch e := expr.(type) {
	case *syntax.Word:
		walkWordParts(e.Parts)
	case *syntax.BinaryTest:
		walkTestExpr(e.X, commands, walkStmts, walkWordParts)
		walkTestExpr(e.Y, commands, walkStmts, walkWordParts)
	case *syntax.UnaryTest:
		walkTestExpr(e.X, commands, walkStmts, walkWordParts)
	case *syntax.ParenTest:
		walkTestExpr(e.X, commands, walkStmts, walkWordParts)
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

	cwd, err := os.Getwd()
	if err != nil {
		log.Debug("cannot get cwd: " + err.Error())
		return cmd, nil
	}
	cwd = filepath.Clean(cwd)

	if resolved != cwd && !strings.HasPrefix(resolved, cwd+string(filepath.Separator)) {
		log.Info("cd target outside cwd, abstaining: " + resolved)
		return cmd, nil
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

	denyRules := extractDenyRules(settings)
	allowPatterns := extractAllowPatterns(settings)

	allAllowed := true
	for _, cmd := range commands {
		for _, rule := range denyRules {
			if globMatch(rule.Pattern, cmd) {
				log.Info("denied cmd=" + cmd)
				return deny(rule.Reason)
			}
		}

		matched := false
		for _, pattern := range allowPatterns {
			if globMatch(pattern, cmd) {
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
