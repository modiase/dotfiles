package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	devlogs "devlogs-lib"
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

var redirectPatterns = []*regexp.Regexp{
	regexp.MustCompile(`[0-9]*>&[0-9]*`),
	regexp.MustCompile(`&>>\s*/dev/null`),
	regexp.MustCompile(`&>\s*/dev/null`),
	regexp.MustCompile(`[0-9]*>>\s*/dev/null`),
	regexp.MustCompile(`[0-9]*>\s*/dev/null`),
}

func stripRedirects(cmd string) string {
	for _, re := range redirectPatterns {
		cmd = re.ReplaceAllString(cmd, "")
	}
	return strings.TrimRight(cmd, " ")
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

	clean := stripRedirects(cmd)
	if clean == "" {
		return abstain()
	}

	settings, err := loadSettings()
	if err != nil {
		log.Debug("no settings: " + err.Error())
		return abstain()
	}

	for _, rule := range extractDenyRules(settings) {
		if globMatch(rule.Pattern, clean) {
			log.Info("denied cmd=" + clean)
			return deny(rule.Reason)
		}
	}

	for _, pattern := range extractAllowPatterns(settings) {
		if globMatch(pattern, clean) {
			log.Info("allowed cmd=" + clean)
			return allow()
		}
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
