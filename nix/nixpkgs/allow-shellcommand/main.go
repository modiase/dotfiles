package main

import (
	"encoding/json"
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
}

func allow() *Decision { return &Decision{Action: "allow"} }

//nolint:unused // part of the Decision API, not yet referenced
func deny() *Decision    { return &Decision{Action: "deny"} }
func abstain() *Decision { return nil }

type hookInput struct {
	ToolName  string `json:"tool_name"`
	ToolInput struct {
		Command string `json:"command"`
	} `json:"tool_input"`
}

type settingsFile struct {
	Permissions struct {
		Allow []string `json:"allow"`
		Deny  []string `json:"deny"`
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

func extractPatterns(settings *settingsFile, key string) []string {
	var raw []string
	if key == "allow" {
		raw = settings.Permissions.Allow
	} else {
		raw = settings.Permissions.Deny
	}

	var patterns []string
	for _, entry := range raw {
		if !strings.HasPrefix(entry, "Bash(") || !strings.HasSuffix(entry, ")") {
			continue
		}
		p := entry[5 : len(entry)-1]
		p = strings.ReplaceAll(p, ":*", "*")
		patterns = append(patterns, p)
	}
	return patterns
}

func globMatch(pattern, s string) bool {
	if strings.HasSuffix(pattern, "*") {
		return strings.HasPrefix(s, pattern[:len(pattern)-1])
	}
	return pattern == s
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

	if !strings.Contains(cmd, "/dev/null") && !strings.Contains(cmd, ">&") {
		return abstain()
	}

	clean := stripRedirects(cmd)
	if clean == "" {
		return abstain()
	}

	settings, err := loadSettings()
	if err != nil {
		log.Debug("no settings: " + err.Error())
		return abstain()
	}

	for _, pattern := range extractPatterns(settings, "deny") {
		if globMatch(pattern, clean) {
			return abstain()
		}
	}

	for _, pattern := range extractPatterns(settings, "allow") {
		if globMatch(pattern, clean) {
			log.Info("allowed cmd=" + clean)
			return allow()
		}
	}

	return abstain()
}

func main() {
	log := devlogs.NewLogger("allow-shellcommand")
	decision := run(log)
	if decision != nil {
		out, _ := json.Marshal(decision)
		fmt.Println(string(out))
	}
}
