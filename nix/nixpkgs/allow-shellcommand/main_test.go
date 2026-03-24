package main

import (
	"encoding/json"
	"testing"
)

func TestStripRedirects(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{"git status 2>/dev/null", "git status"},
		{"git status 2>&1", "git status"},
		{"cmd &>/dev/null", "cmd"},
		{"cmd &>>/dev/null", "cmd"},
		{"cmd >/dev/null 2>&1", "cmd"},
		{"cmd >>/dev/null", "cmd"},
		{"echo hello", "echo hello"},
		{"", ""},
	}

	for _, tt := range tests {
		got := stripRedirects(tt.input)
		if got != tt.want {
			t.Errorf("stripRedirects(%q) = %q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestExtractAllowPatterns(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.Allow = []string{
		"Bash(git status:*)",
		"Bash(nix build:*)",
		"Read(~/.ssh/*)",
	}

	allow := extractAllowPatterns(settings)
	if len(allow) != 2 {
		t.Fatalf("expected 2 allow patterns, got %d: %v", len(allow), allow)
	}
	if allow[0] != "git status*" {
		t.Errorf("allow[0] = %q, want %q", allow[0], "git status*")
	}
	if allow[1] != "nix build*" {
		t.Errorf("allow[1] = %q, want %q", allow[1], "nix build*")
	}
}

func TestExtractDenyRulesStringFormat(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.DenyRaw = []json.RawMessage{
		json.RawMessage(`"Bash(rm -rf:*)"`),
	}

	rules := extractDenyRules(settings)
	if len(rules) != 1 {
		t.Fatalf("expected 1 deny rule, got %d: %v", len(rules), rules)
	}
	if rules[0].Pattern != "rm -rf*" {
		t.Errorf("pattern = %q, want %q", rules[0].Pattern, "rm -rf*")
	}
	if rules[0].Reason != "Command denied by policy." {
		t.Errorf("reason = %q, want %q", rules[0].Reason, "Command denied by policy.")
	}
}

func TestExtractDenyRulesObjectFormat(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.DenyRaw = []json.RawMessage{
		json.RawMessage(`{"rule":"Bash(git push:*)","reason":"Ask the user."}`),
	}

	rules := extractDenyRules(settings)
	if len(rules) != 1 {
		t.Fatalf("expected 1 deny rule, got %d: %v", len(rules), rules)
	}
	if rules[0].Pattern != "git push*" {
		t.Errorf("pattern = %q, want %q", rules[0].Pattern, "git push*")
	}
	if rules[0].Reason != "Ask the user." {
		t.Errorf("reason = %q, want %q", rules[0].Reason, "Ask the user.")
	}
}

func TestExtractDenyRulesMixed(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.DenyRaw = []json.RawMessage{
		json.RawMessage(`"Bash(rm -rf:*)"`),
		json.RawMessage(`{"rule":"Bash(git push:*)","reason":"Destructive."}`),
		json.RawMessage(`"Read(~/.ssh/*)"`),
	}

	rules := extractDenyRules(settings)
	if len(rules) != 2 {
		t.Fatalf("expected 2 deny rules, got %d: %v", len(rules), rules)
	}
	if rules[0].Pattern != "rm -rf*" || rules[0].Reason != "Command denied by policy." {
		t.Errorf("rules[0] = %+v", rules[0])
	}
	if rules[1].Pattern != "git push*" || rules[1].Reason != "Destructive." {
		t.Errorf("rules[1] = %+v", rules[1])
	}
}

func TestExtractDenyRulesObjectNoReason(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.DenyRaw = []json.RawMessage{
		json.RawMessage(`{"rule":"Bash(node:*)"}`),
	}

	rules := extractDenyRules(settings)
	if len(rules) != 1 {
		t.Fatalf("expected 1 deny rule, got %d", len(rules))
	}
	if rules[0].Reason != "Command denied by policy." {
		t.Errorf("reason = %q, want default", rules[0].Reason)
	}
}

func TestDenyDecisionHasReason(t *testing.T) {
	d := deny("test reason")
	if d.Action != "deny" {
		t.Errorf("action = %q, want %q", d.Action, "deny")
	}
	if d.Reason != "test reason" {
		t.Errorf("reason = %q, want %q", d.Reason, "test reason")
	}

	out, err := json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"permissionDecision":"deny","permissionDecisionReason":"test reason"}`
	if string(out) != want {
		t.Errorf("json = %s, want %s", out, want)
	}
}

func TestAllowDecisionNoReason(t *testing.T) {
	d := allow()
	out, err := json.Marshal(d)
	if err != nil {
		t.Fatal(err)
	}
	want := `{"permissionDecision":"allow"}`
	if string(out) != want {
		t.Errorf("json = %s, want %s", out, want)
	}
}

func TestGlobMatch(t *testing.T) {
	tests := []struct {
		pattern string
		s       string
		want    bool
	}{
		{"git status*", "git status", true},
		{"git status*", "git status --short", true},
		{"git status*", "git log", false},
		{"echo hello", "echo hello", true},
		{"echo hello", "echo hello world", false},
		{"git -C * show*", "git -C /Users/moye/dotfiles show HEAD --stat", true},
		{"git -C * show*", "git -C /tmp/repo show abc123", true},
		{"git -C * show*", "git log --oneline", false},
		{"git*status*", "git -C /foo status --short", true},
		{"a*b*c", "aXbYc", true},
		{"a*b*c", "abc", true},
		{"a*b*c", "aXYc", false},
		{"a*b*c", "aXbY", false},
		{"git*", "git status", true},
		{"*git", "sudo git", true},
		{"*git", "sudo git status", false},
	}

	for _, tt := range tests {
		got := globMatch(tt.pattern, tt.s)
		if got != tt.want {
			t.Errorf("globMatch(%q, %q) = %v, want %v", tt.pattern, tt.s, got, tt.want)
		}
	}
}
