package main

import (
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

func TestExtractPatterns(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.Allow = []string{
		"Bash(git status:*)",
		"Bash(nix build:*)",
		"Read(~/.ssh/*)",
	}
	settings.Permissions.Deny = []string{
		"Bash(rm -rf:*)",
	}

	allow := extractPatterns(settings, "allow")
	if len(allow) != 2 {
		t.Fatalf("expected 2 allow patterns, got %d: %v", len(allow), allow)
	}
	if allow[0] != "git status*" {
		t.Errorf("allow[0] = %q, want %q", allow[0], "git status*")
	}
	if allow[1] != "nix build*" {
		t.Errorf("allow[1] = %q, want %q", allow[1], "nix build*")
	}

	deny := extractPatterns(settings, "deny")
	if len(deny) != 1 || deny[0] != "rm -rf*" {
		t.Errorf("deny = %v, want [\"rm -rf*\"]", deny)
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
		// Mid-string wildcards
		{"git -C * show*", "git -C /Users/moye/dotfiles show HEAD --stat", true},
		{"git -C * show*", "git -C /tmp/repo show abc123", true},
		{"git -C * show*", "git log --oneline", false},
		{"git*status*", "git -C /foo status --short", true},
		// Multiple wildcards
		{"a*b*c", "aXbYc", true},
		{"a*b*c", "abc", true},
		{"a*b*c", "aXYc", false},
		{"a*b*c", "aXbY", false},
		// Trailing empty after split
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
