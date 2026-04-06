package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

	devlogs "devlogs-lib"
	"mvdan.cc/sh/v3/syntax"
)

func commandStrings(infos []commandInfo) []string {
	out := make([]string, len(infos))
	for i, ci := range infos {
		out[i] = ci.Command
	}
	return out
}

func TestRedirectsExcludedFromExtraction(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"git status 2>/dev/null", []string{"git status"}},
		{"git status 2>&1", []string{"git status"}},
		{"cmd &>/dev/null", []string{"cmd"}},
		{"cmd >/dev/null 2>&1", []string{"cmd"}},
		{"echo hello", []string{"echo hello"}},
		{"git status > /tmp/out", []string{"git status"}},
		{"echo '2>/dev/null'", []string{"echo 2>/dev/null"}},
	}

	for _, tt := range tests {
		raw, err := extractCommands(tt.input)
		if err != nil {
			t.Errorf("extractCommands(%q) error: %v", tt.input, err)
			continue
		}
		got := commandStrings(raw)
		if len(got) != len(tt.want) {
			t.Errorf("extractCommands(%q) = %v, want %v", tt.input, got, tt.want)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("extractCommands(%q)[%d] = %q, want %q", tt.input, i, got[i], tt.want[i])
			}
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

func TestExtractDenyRulesFromSettings(t *testing.T) {
	settings := &settingsFile{}
	settings.Permissions.Deny = []string{
		"Bash(rm -rf:*)",
		"Read(~/.ssh/*)",
	}

	rules := extractDenyRules(settings)
	if len(rules) != 1 {
		t.Fatalf("expected 1 deny rule (non-Bash skipped), got %d: %v", len(rules), rules)
	}
	if rules[0].Pattern != "rm -rf*" {
		t.Errorf("pattern = %q, want %q", rules[0].Pattern, "rm -rf*")
	}
	if rules[0].Reason != "Command denied by policy." {
		t.Errorf("reason = %q, want %q", rules[0].Reason, "Command denied by policy.")
	}
}

func TestLoadEmbeddedDenyRules(t *testing.T) {
	orig := embeddedDenyRulesJSON
	defer func() { embeddedDenyRulesJSON = orig }()

	embeddedDenyRulesJSON = []byte(`[
		{"rule":"Bash(git push:*)","reason":"Ask the user."},
		{"rule":"Bash(node:*)"},
		{"rule":"Read(~/.ssh/*)","reason":"skipped"}
	]`)

	rules := loadEmbeddedDenyRules()
	if len(rules) != 2 {
		t.Fatalf("expected 2 rules (non-Bash skipped), got %d: %v", len(rules), rules)
	}
	if rules[0].Pattern != "git push*" || rules[0].Reason != "Ask the user." {
		t.Errorf("rules[0] = %+v", rules[0])
	}
	if rules[1].Pattern != "node*" || rules[1].Reason != "Command denied by policy." {
		t.Errorf("rules[1] = %+v, want default reason", rules[1])
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
	want := `{"permissionDecision":"deny","permissionDecisionReason":"test reason","retry":true}`
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

func TestFirstSeparator(t *testing.T) {
	tests := []struct {
		input   string
		wantIdx int
		wantSep string
	}{
		{"foo && bar", 4, "&&"},
		{"foo; bar", 3, ";"},
		{"foo || bar", 4, "||"},
		{"foo; bar && baz", 3, ";"},
		{"foo && bar; baz", 4, "&&"},
		{"foo || bar && baz", 4, "||"},
		{"no separators here", -1, ""},
	}
	for _, tt := range tests {
		idx, sep := firstSeparator(tt.input)
		if idx != tt.wantIdx || sep != tt.wantSep {
			t.Errorf("firstSeparator(%q) = (%d, %q), want (%d, %q)", tt.input, idx, sep, tt.wantIdx, tt.wantSep)
		}
	}
}

func TestStripCdPrefix(t *testing.T) {
	log := devlogs.NewLogger("test")

	t.Run("non-cd command passes through", func(t *testing.T) {
		cmd, d := stripCdPrefix("git status", log)
		if d != nil {
			t.Fatal("expected nil decision")
		}
		if cmd != "git status" {
			t.Errorf("cmd = %q, want %q", cmd, "git status")
		}
	})

	t.Run("cd to cwd with trailing command", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := "cd " + cwd + " && git log --oneline -5"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "git log --oneline -5" {
			t.Errorf("cmd = %q, want %q", cmd, "git log --oneline -5")
		}
	})

	t.Run("cd to subdirectory with trailing command", func(t *testing.T) {
		cwd, _ := os.Getwd()
		sub := filepath.Join(cwd, "subdir")
		input := "cd " + sub + " && ls -la"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "ls -la" {
			t.Errorf("cmd = %q, want %q", cmd, "ls -la")
		}
	})

	t.Run("bare cd to cwd is allowed", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := "cd " + cwd
		cmd, d := stripCdPrefix(input, log)
		if d == nil || d.Action != "allow" {
			t.Fatalf("expected allow decision, got cmd=%q d=%v", cmd, d)
		}
	})

	t.Run("cd outside cwd passes through unchanged", func(t *testing.T) {
		input := "cd /tmp && git log"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd to parent passes through unchanged", func(t *testing.T) {
		input := "cd .. && git status"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd with quoted path", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := `cd "` + cwd + `" && echo hello`
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "echo hello" {
			t.Errorf("cmd = %q, want %q", cmd, "echo hello")
		}
	})

	t.Run("cd with single-quoted path", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := "cd '" + cwd + "' && echo hello"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "echo hello" {
			t.Errorf("cmd = %q, want %q", cmd, "echo hello")
		}
	})

	t.Run("cd with semicolon separator", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := "cd " + cwd + "; git log"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "git log" {
			t.Errorf("cmd = %q, want %q", cmd, "git log")
		}
	})

	t.Run("bare cd with no args abstains", func(t *testing.T) {
		input := "cd "
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd with tilde abstains", func(t *testing.T) {
		input := "cd ~ && ls"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd with shell variable abstains", func(t *testing.T) {
		input := "cd $HOME && ls"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd with command substitution abstains", func(t *testing.T) {
		input := "cd $(pwd) && ls"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("cd with || separator", func(t *testing.T) {
		input := "cd /nonexistent || echo fallback"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision (abstain), got", d)
		}
		if cmd != input {
			t.Errorf("cmd = %q, want %q (unchanged)", cmd, input)
		}
	})

	t.Run("semicolon before && picks semicolon", func(t *testing.T) {
		cwd, _ := os.Getwd()
		input := "cd " + cwd + "; echo a && echo b"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "echo a && echo b" {
			t.Errorf("cmd = %q, want %q", cmd, "echo a && echo b")
		}
	})

	t.Run("cd to relative dot", func(t *testing.T) {
		input := "cd . && ls"
		cmd, d := stripCdPrefix(input, log)
		if d != nil {
			t.Fatal("expected nil decision, got", d)
		}
		if cmd != "ls" {
			t.Errorf("cmd = %q, want %q", cmd, "ls")
		}
	})
}

func TestExtractCommands(t *testing.T) {
	tests := []struct {
		input string
		want  []string
	}{
		{"git status", []string{"git status"}},
		{"git diff | head -5", []string{"git diff", "head -5"}},
		{"git diff && git log", []string{"git diff", "git log"}},
		{"echo a; echo b", []string{"echo a", "echo b"}},
		{"echo a |& cat", []string{"echo a", "cat"}},
		{"echo $(whoami)", []string{"whoami", "echo $(whoami)"}},
		{"git diff | rm -rf /", []string{"git diff", "rm -rf /"}},
		{"echo 'a | b'", []string{"echo a | b"}},
		{"cmd1 && cmd2 | cmd3 ; cmd4", []string{"cmd1", "cmd2", "cmd3", "cmd4"}},
		{"git diff <(git show HEAD)", []string{"git show HEAD", "git diff <(git show HEAD)"}},
		{"git log & rm -rf /", []string{"git log", "rm -rf /"}},

		// if/elif/else
		{"if true; then echo a; fi", []string{"true", "echo a"}},
		{"if true; then echo a; elif false; then echo b; else echo c; fi", []string{"true", "echo a", "false", "echo b", "echo c"}},

		// while/for/case
		{"while true; do echo a; done", []string{"true", "echo a"}},
		{"for x in a; do echo $x; done", []string{"echo $x"}},
		{"case x in x) echo matched;; esac", []string{"echo matched"}},

		// function declarations
		{"f() { echo a; }", []string{"echo a"}},

		// time/coproc
		{"time echo a", []string{"echo a"}},

		// subshell and brace group
		{"(echo a; echo b)", []string{"echo a", "echo b"}},
		{"{ echo a; echo b; }", []string{"echo a", "echo b"}},

		// double-quoted command substitution
		{`echo "$(whoami)"`, []string{"whoami", `echo "$(whoami)"`}},
		{`git log "$(rm -rf /)"`, []string{"rm -rf /", `git log "$(rm -rf /)"`}},

		// backtick command substitution
		// printer normalises backticks to $()
		{"echo `whoami`", []string{"whoami", "echo $(whoami)"}},

		// nested substitutions
		{"echo $(echo $(whoami))", []string{"whoami", "echo $(whoami)", "echo $(echo $(whoami))"}},

		// assignment with command substitution
		{"FOO=$(rm -rf /)", []string{"rm -rf /"}},
		{"export FOO=$(rm -rf /)", []string{"rm -rf /"}},

		// redirect with command substitution
		{"echo foo > $(rm -rf /)", []string{"rm -rf /", "echo foo"}},

		// for-loop iteration list with command substitution
		{"for x in $(whoami); do echo $x; done", []string{"whoami", "echo $x"}},

		// case subject with command substitution
		{"case $(whoami) in root) echo yes;; esac", []string{"whoami", "echo yes"}},

		// parameter expansion: replacement, slice, index
		{`echo ${x/$(whoami)/y}`, []string{"whoami", `echo ${x/$(whoami)/y}`}},
		{`echo ${x:0:$(whoami)}`, []string{"whoami", `echo ${x:0:$(whoami)}`}},
		{`echo ${arr[$(whoami)]}`, []string{"whoami", `echo ${arr[$(whoami)]}`}},

		// array assignment with command substitution
		{"x=($(whoami))", []string{"whoami"}},
		{"declare -a arr=($(whoami))", []string{"whoami"}},

		// quoting is stripped for simple words (bypass prevention)
		{`'rm' '-rf' '/'`, []string{"rm -rf /"}},
		{`"rm" "-rf" "/"`, []string{"rm -rf /"}},
		{`'rm' -rf /`, []string{"rm -rf /"}},

		// multi-part word concatenation (quote splicing)
		{`r""m -rf /`, []string{"rm -rf /"}},
		{`r''m -rf /`, []string{"rm -rf /"}},
		{`'r'"m" -rf /`, []string{"rm -rf /"}},
		{`r'm' -rf /`, []string{"rm -rf /"}},
		{`r"m" -rf /`, []string{"rm -rf /"}},

		// backslash escape stripping
		{`r\m -rf /`, []string{"rm -rf /"}},
		{`\r\m -rf /`, []string{"rm -rf /"}},
		{`gi\t status`, []string{"git status"}},

		// redirect on piped command (BinaryCmd child stmt)
		{"echo foo > $(whoami) | cat", []string{"whoami", "echo foo", "cat"}},

		// quoting with embedded expansions preserved
		{`echo "hello $(whoami)"`, []string{"whoami", `echo "hello $(whoami)"`}},

		// ANSI-C quoting ($'...') falls back to printed form
		{`$'\x72\x6d' -rf /`, []string{`$'\x72\x6d' -rf /`}},
		{`$'\162\155' -rf /`, []string{`$'\162\155' -rf /`}},
		{`r$'\x6d' -rf /`, []string{`r$'\x6d' -rf /`}},
		{`$'\u0072\u006d' -rf /`, []string{`$'\u0072\u006d' -rf /`}},

		// env var prefix: both full form and args-only form extracted
		{"PATH=/evil git status", []string{"PATH=/evil git status", "git status"}},
		{"FOO=bar BAZ=qux rm -rf /", []string{"FOO=bar BAZ=qux rm -rf /", "rm -rf /"}},
		{"LD_PRELOAD=/evil.so git status", []string{"LD_PRELOAD=/evil.so git status", "git status"}},

		// SSH unwrapping
		{"ssh hermes 'git status'", []string{"git status"}},
		{"ssh hermes systemctl status foo", []string{"systemctl status foo"}},
		{"ssh hermes 'cmd1; cmd2'", []string{"cmd1", "cmd2"}},
		{"ssh hermes 'cmd1 && cmd2'", []string{"cmd1", "cmd2"}},
		{"ssh hermes 'cmd1 | cmd2'", []string{"cmd1", "cmd2"}},
		{"ssh hermes 'echo hello'", []string{"echo hello"}},
		{"ssh user@host 'git status'", []string{"git status"}},
		{"ssh hermes 'ssh inner git status'", []string{"git status"}},

		// SSH with various flags
		{"ssh -v hermes 'git status'", []string{"git status"}},
		{"ssh -vvv hermes 'git status'", []string{"git status"}},
		{"ssh -p 2222 hermes 'ls -la'", []string{"ls -la"}},
		{"ssh -p2222 hermes 'ls -la'", []string{"ls -la"}},
		{"ssh -o StrictHostKeyChecking=no hermes 'git status'", []string{"git status"}},
		{"ssh -oStrictHostKeyChecking=no hermes 'git log'", []string{"git log"}},
		{"ssh -i /tmp/key hermes 'git status'", []string{"git status"}},
		{"ssh -L 8080:localhost:80 hermes 'git log'", []string{"git log"}},
		{"ssh -J jumphost hermes 'git status'", []string{"git status"}},
		{"ssh -vp 2222 -i /tmp/key hermes 'git status'", []string{"git status"}},
		{"ssh -- hermes 'git status'", []string{"git status"}},

		// SSH kept as-is (no unwrap)
		{"ssh hermes", []string{"ssh hermes"}},

		// SSH with unresolvable args (walkWords catches substitutions)
		{`ssh hermes "$(whoami)"`, []string{"whoami", `ssh hermes "$(whoami)"`}},

		// bash/sh/zsh -c unwrapping
		{"bash -c 'git status'", []string{"git status"}},
		{"sh -c 'git status'", []string{"git status"}},
		{"zsh -c 'git status'", []string{"git status"}},
		{"bash -c 'cmd1; cmd2'", []string{"cmd1", "cmd2"}},
		{"bash -c 'cmd1 | cmd2'", []string{"cmd1", "cmd2"}},
		{"bash -xc 'git status'", []string{"git status"}},
		{"bash -x -e -c 'git status'", []string{"git status"}},
		{"bash -c 'echo $1' _ foo", []string{"echo $1"}},
		{"bash -c 'ssh hermes git status'", []string{"git status"}},
		{`ssh hermes 'bash -c "git status"'`, []string{"git status"}},

		// bash/sh kept as-is (no unwrap)
		{"bash", []string{"bash"}},
		{"bash script.sh", []string{"bash script.sh"}},
		{"bash -x script.sh", []string{"bash -x script.sh"}},

		// nix-shell unwrapping
		{"nix-shell --run 'git status'", []string{"git status"}},
		{"nix-shell -p git --run 'git status'", []string{"git status"}},
		{"nix-shell --pure -p git --run 'git log; git diff'", []string{"git log", "git diff"}},
		{"nix-shell --command 'git status'", []string{"git status"}},
		{"nix-shell --run 'cmd1 | cmd2'", []string{"cmd1", "cmd2"}},

		// nix-shell kept as-is (no unwrap)
		{"nix-shell", []string{"nix-shell"}},
		{"nix-shell -p git", []string{"nix-shell -p git"}},
		{"nix-shell default.nix", []string{"nix-shell default.nix"}},

		// nix develop/shell unwrapping
		{"nix develop --command git status", []string{"git status"}},
		{"nix develop .#foo --command git log --oneline", []string{"git log --oneline"}},
		{"nix shell nixpkgs#git --command git status", []string{"git status"}},
		{`nix shell nixpkgs#git --command bash -c 'git status'`, []string{"git status"}},

		// nix kept as-is (no unwrap)
		{"nix build .#foo", []string{"nix build .#foo"}},
		{"nix develop", []string{"nix develop"}},
		{"nix shell nixpkgs#git", []string{"nix shell nixpkgs#git"}},
		{"nix flake show", []string{"nix flake show"}},
	}
	for _, tt := range tests {
		raw, err := extractCommands(tt.input)
		if err != nil {
			t.Errorf("extractCommands(%q) error: %v", tt.input, err)
			continue
		}
		got := commandStrings(raw)
		if len(got) != len(tt.want) {
			t.Errorf("extractCommands(%q) = %v, want %v", tt.input, got, tt.want)
			continue
		}
		for i := range got {
			if got[i] != tt.want[i] {
				t.Errorf("extractCommands(%q)[%d] = %q, want %q", tt.input, i, got[i], tt.want[i])
			}
		}
	}
}

func TestPipeSmuggling(t *testing.T) {
	dir := t.TempDir()
	settingsPath := filepath.Join(dir, "settings.json")
	settings := `{
		"permissions": {
			"allow": ["Bash(git*)"],
			"deny": ["Bash(rm -rf*)"]
		}
	}`
	_ = os.WriteFile(settingsPath, []byte(settings), 0o644)
	t.Setenv("CLAUDE_CONFIG_DIR", dir)

	tests := []struct {
		cmd  string
		want string
	}{
		{"git status", "allow"},
		{"git diff | rm -rf /", "deny"},
		{"git diff | head -5", "abstain"},
		{"git diff && git log", "allow"},
		{"git diff; rm -rf /", "deny"},
		{"git log || rm -rf /", "deny"},
		{"echo $(rm -rf /)", "deny"},
		{"git diff <(git show HEAD)", "allow"},
		{"git log & rm -rf /", "deny"},

		// control flow smuggling
		{"if true; then rm -rf /; fi", "deny"},
		{"while true; do rm -rf /; done", "deny"},
		{"for x in a; do rm -rf /; done", "deny"},
		{"case x in x) rm -rf /;; esac", "deny"},
		{"git status; if true; then rm -rf /; fi", "deny"},

		// function smuggling
		{"f() { rm -rf /; }; f", "deny"},

		// time/coproc smuggling
		{"time rm -rf /", "deny"},

		// double-quoted substitution smuggling
		{`git log "$(rm -rf /)"`, "deny"},

		// assignment smuggling
		{"FOO=$(rm -rf /)", "deny"},
		{"export FOO=$(rm -rf /)", "deny"},

		// redirect smuggling
		{"git status > $(rm -rf /)", "deny"},

		// nested substitution smuggling
		{"echo $(echo $(rm -rf /))", "deny"},

		// process substitution with denied command
		{"git diff <(rm -rf /)", "deny"},

		// for-loop iteration smuggling
		{"for x in $(rm -rf /); do git status; done", "deny"},

		// case subject smuggling
		{"case $(rm -rf /) in *) git status;; esac", "deny"},

		// parameter expansion smuggling
		{`echo ${x/$(rm -rf /)/y}`, "deny"},
		{`echo ${x:0:$(rm -rf /)}`, "deny"},

		// array assignment smuggling
		{"x=($(rm -rf /))", "deny"},
		{"declare -a arr=($(rm -rf /))", "deny"},

		// quoting bypass
		{`'rm' '-rf' '/'`, "deny"},
		{`"rm" "-rf" "/"`, "deny"},
		{`'rm' -rf /`, "deny"},

		// quote splicing bypass
		{`r""m -rf /`, "deny"},
		{`r''m -rf /`, "deny"},
		{`'r'"m" -rf /`, "deny"},

		// backslash escape bypass
		{`r\m -rf /`, "deny"},
		{`\r\m -rf /`, "deny"},

		// backslash escape on allowed command
		{`gi\t status`, "allow"},

		// redirect on BinaryCmd child
		{"echo foo > $(rm -rf /) | git status", "deny"},

		// ANSI-C quoting bypass (hex/octal/unicode encoding of command name)
		{`$'\x72\x6d' -rf /`, "abstain"},
		{`$'\162\155' -rf /`, "abstain"},
		{`r$'\x6d' -rf /`, "abstain"},
		{`$'\u0072\u006d' -rf /`, "abstain"},
		{`$'\x67\x69\x74' status`, "abstain"},

		// redirects should not interfere with allow matching
		{"git status 2>/dev/null", "allow"},
		{"git log > /tmp/out", "allow"},

		// env var prefix smuggling — assigns must be part of the match
		{"PATH=/evil git status", "abstain"},
		{"LD_PRELOAD=/evil.so git status", "abstain"},
		{"FOO=bar rm -rf /", "deny"},

		// parse failure → abstain (not fallback to whole-string match)
		{"git status '", "abstain"},

		// SSH wrapper unwrapping
		{"ssh hermes 'git status'", "allow"},
		{"ssh hermes 'git diff --stat'", "allow"},
		{"ssh hermes 'git log; git diff'", "allow"},
		{"ssh -p 2222 hermes 'git status'", "allow"},
		{"ssh -v hermes 'git status'", "allow"},
		{"ssh hermes 'rm -rf /'", "deny"},
		{"ssh hermes 'git status; rm -rf /'", "deny"},
		{"ssh hermes", "abstain"},
		{"ssh hermes ls", "abstain"},
		{`ssh hermes "$(rm -rf /)"`, "deny"},
		{"ssh hermes 'ssh inner git status'", "allow"},
		{"FOO=bar ssh hermes 'git status'", "abstain"},

		// bash/sh/zsh -c unwrapping
		{"bash -c 'git status'", "allow"},
		{"sh -c 'git status'", "allow"},
		{"zsh -c 'git status'", "allow"},
		{"bash -c 'git log; git diff'", "allow"},
		{"bash -c 'rm -rf /'", "deny"},
		{"bash -c 'git status; rm -rf /'", "deny"},
		{"bash", "abstain"},
		{"bash script.sh", "abstain"},
		{`bash -c "$(rm -rf /)"`, "deny"},
		{"bash -c 'ssh hermes git status'", "allow"},
		{`ssh hermes 'bash -c "git status"'`, "allow"},

		// nix-shell unwrapping
		{"nix-shell --run 'git status'", "allow"},
		{"nix-shell -p git --run 'git diff'", "allow"},
		{"nix-shell --run 'rm -rf /'", "deny"},
		{"nix-shell --run 'git status; rm -rf /'", "deny"},
		{"nix-shell -p git", "abstain"},
		{"nix-shell", "abstain"},

		// nix develop/shell unwrapping
		{"nix develop --command git status", "allow"},
		{"nix shell nixpkgs#git --command git log", "allow"},
		{"nix develop --command rm -rf /", "deny"},
		{"nix develop", "abstain"},
		{"nix build .#foo", "abstain"},
	}

	for _, tt := range tests {
		t.Run(tt.cmd, func(t *testing.T) {
			input := hookInput{}
			input.ToolInput.Command = tt.cmd
			data, _ := json.Marshal(input)

			r, w, _ := os.Pipe()
			_, _ = w.Write(data)
			_ = w.Close()
			origStdin := os.Stdin
			os.Stdin = r
			defer func() { os.Stdin = origStdin }()

			log := devlogs.NewLogger("test")
			got := run(log)

			var action string
			switch {
			case got == nil:
				action = "abstain"
			case got.Action == "allow":
				action = "allow"
			case got.Action == "deny":
				action = "deny"
			}

			if action != tt.want {
				t.Errorf("run(%q) = %s, want %s", tt.cmd, action, tt.want)
			}
		})
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

func TestExtractCommandsCaptured(t *testing.T) {
	tests := []struct {
		input        string
		wantCommands []string
		wantCaptured []bool
	}{
		{
			"gcloud secrets versions access latest --secret=foo",
			[]string{"gcloud secrets versions access latest --secret=foo"},
			[]bool{false},
		},
		{
			"x=$(gcloud secrets versions access latest)",
			[]string{"gcloud secrets versions access latest"},
			[]bool{true},
		},
		{
			"gcloud secrets versions access latest | sha256sum",
			[]string{"gcloud secrets versions access latest", "sha256sum"},
			[]bool{true, false},
		},
		{
			"gcloud secrets versions access latest |& sha256sum",
			[]string{"gcloud secrets versions access latest", "sha256sum"},
			[]bool{true, false},
		},
		{
			"a | b | c",
			[]string{"a", "b", "c"},
			[]bool{true, true, false},
		},
		{
			"gcloud secrets versions access latest && echo done",
			[]string{"gcloud secrets versions access latest", "echo done"},
			[]bool{false, false},
		},
		{
			"gcloud secrets versions access latest || echo failed",
			[]string{"gcloud secrets versions access latest", "echo failed"},
			[]bool{false, false},
		},
		{
			"gcloud secrets versions access latest; echo done",
			[]string{"gcloud secrets versions access latest", "echo done"},
			[]bool{false, false},
		},
		{
			"diff <(gcloud secrets versions access 1) <(gcloud secrets versions access 2)",
			[]string{
				"gcloud secrets versions access 1",
				"gcloud secrets versions access 2",
				"diff <(gcloud secrets versions access 1) <(gcloud secrets versions access 2)",
			},
			[]bool{true, true, false},
		},
		{
			`echo "$(gcloud secrets versions access latest)"`,
			[]string{"gcloud secrets versions access latest", `echo "$(gcloud secrets versions access latest)"`},
			[]bool{true, false},
		},
		{
			"echo $(echo $(whoami))",
			[]string{"whoami", "echo $(whoami)", "echo $(echo $(whoami))"},
			[]bool{true, true, false},
		},
		{
			"FOO=$(whoami)",
			[]string{"whoami"},
			[]bool{true},
		},
		{
			"a && b | c",
			[]string{"a", "b", "c"},
			[]bool{false, true, false},
		},
		{
			"if true; then gcloud secrets versions access latest; fi",
			[]string{"true", "gcloud secrets versions access latest"},
			[]bool{false, false},
		},
		{
			"(gcloud secrets versions access latest)",
			[]string{"gcloud secrets versions access latest"},
			[]bool{false},
		},
		{
			"{ gcloud secrets versions access latest; }",
			[]string{"gcloud secrets versions access latest"},
			[]bool{false},
		},
		{
			"x=$(a | b)",
			[]string{"a", "b"},
			[]bool{true, true},
		},
		{
			"a & b",
			[]string{"a", "b"},
			[]bool{false, false},
		},
		{
			"echo foo > $(whoami)",
			[]string{"whoami", "echo foo"},
			[]bool{true, false},
		},
		{
			"for x in $(whoami); do echo $x; done",
			[]string{"whoami", "echo $x"},
			[]bool{true, false},
		},
		{
			"PATH=/evil git status",
			[]string{"PATH=/evil git status", "git status"},
			[]bool{false, false},
		},
		{
			"x=$(PATH=/evil git status)",
			[]string{"PATH=/evil git status", "git status"},
			[]bool{true, true},
		},

		// SSH captured propagation
		{
			"ssh hermes 'git status'",
			[]string{"git status"},
			[]bool{false},
		},
		{
			"ssh hermes 'git status' | head -5",
			[]string{"git status", "head -5"},
			[]bool{true, false},
		},
		{
			"ssh hermes 'git log | head'",
			[]string{"git log", "head"},
			[]bool{true, false},
		},
		{
			"ssh hermes 'a | b' | cat",
			[]string{"a", "b", "cat"},
			[]bool{true, true, false},
		},
		{
			"ssh hermes 'a; b'",
			[]string{"a", "b"},
			[]bool{false, false},
		},
		{
			"ssh hermes 'a && b' | cat",
			[]string{"a", "b", "cat"},
			[]bool{true, true, false},
		},

		// bash -c captured propagation
		{
			"bash -c 'git status'",
			[]string{"git status"},
			[]bool{false},
		},
		{
			"bash -c 'git status' | head -5",
			[]string{"git status", "head -5"},
			[]bool{true, false},
		},
		{
			"bash -c 'a | b'",
			[]string{"a", "b"},
			[]bool{true, false},
		},
		{
			"bash -c 'a | b' | cat",
			[]string{"a", "b", "cat"},
			[]bool{true, true, false},
		},

		// nix-shell captured propagation
		{
			"nix-shell --run 'git status'",
			[]string{"git status"},
			[]bool{false},
		},
		{
			"nix-shell --run 'git status' | head -5",
			[]string{"git status", "head -5"},
			[]bool{true, false},
		},
		{
			"nix-shell --run 'a | b'",
			[]string{"a", "b"},
			[]bool{true, false},
		},

		// nix develop captured propagation
		{
			"nix develop --command git status",
			[]string{"git status"},
			[]bool{false},
		},
		{
			"nix develop --command git status | head -5",
			[]string{"git status", "head -5"},
			[]bool{true, false},
		},
	}
	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			got, err := extractCommands(tt.input)
			if err != nil {
				t.Fatalf("extractCommands(%q) error: %v", tt.input, err)
			}
			if len(got) != len(tt.wantCommands) {
				t.Fatalf("extractCommands(%q) returned %d commands %v, want %d %v",
					tt.input, len(got), got, len(tt.wantCommands), tt.wantCommands)
			}
			for i := range got {
				if got[i].Command != tt.wantCommands[i] {
					t.Errorf("[%d] command = %q, want %q", i, got[i].Command, tt.wantCommands[i])
				}
				if got[i].Captured != tt.wantCaptured[i] {
					t.Errorf("[%d] %q captured = %v, want %v", i, got[i].Command, got[i].Captured, tt.wantCaptured[i])
				}
			}
		})
	}
}

func TestEmbeddedDenyRulesTopLevelOnly(t *testing.T) {
	orig := embeddedDenyRulesJSON
	defer func() { embeddedDenyRulesJSON = orig }()

	embeddedDenyRulesJSON = []byte(`[
		{"rule":"Bash(gcloud secrets versions access:*)","reason":"No secrets.","topLevelOnly":true},
		{"rule":"Bash(rm -rf:*)","reason":"Destructive."}
	]`)

	rules := loadEmbeddedDenyRules()
	if len(rules) != 2 {
		t.Fatalf("expected 2 deny rules, got %d: %v", len(rules), rules)
	}

	if rules[0].Pattern != "gcloud secrets versions access*" {
		t.Errorf("rules[0].Pattern = %q, want %q", rules[0].Pattern, "gcloud secrets versions access*")
	}
	if !rules[0].TopLevelOnly {
		t.Errorf("rules[0].TopLevelOnly = false, want true")
	}
	if rules[0].Reason != "No secrets." {
		t.Errorf("rules[0].Reason = %q, want %q", rules[0].Reason, "No secrets.")
	}

	if rules[1].TopLevelOnly {
		t.Errorf("rules[1].TopLevelOnly = true, want false (default)")
	}
}

func TestTopLevelOnlyDeny(t *testing.T) {
	orig := embeddedDenyRulesJSON
	defer func() { embeddedDenyRulesJSON = orig }()

	embeddedDenyRulesJSON = []byte(`[
		{"rule":"Bash(gcloud secrets versions access:*)","reason":"Do not directly view secrets.","topLevelOnly":true}
	]`)

	dir := t.TempDir()
	settingsPath := filepath.Join(dir, "settings.json")
	settings := `{
		"permissions": {
			"allow": ["Bash(gcloud*)", "Bash(git*)", "Bash(sha256sum*)", "Bash(diff*)", "Bash(echo*)", "Bash(true*)"],
			"deny": ["Bash(rm -rf*)"]
		}
	}`
	_ = os.WriteFile(settingsPath, []byte(settings), 0o644)
	t.Setenv("CLAUDE_CONFIG_DIR", dir)

	tests := []struct {
		cmd  string
		want string
	}{
		{"gcloud secrets versions access latest --secret=foo", "deny"},
		{"x=$(gcloud secrets versions access latest --secret=foo)", "allow"},
		{"gcloud secrets versions access latest --secret=foo | sha256sum", "allow"},
		{"gcloud secrets versions access latest --secret=foo | diff - expected.txt", "allow"},
		{"diff <(gcloud secrets versions access 1 --secret=foo) <(gcloud secrets versions access 2 --secret=foo)", "allow"},
		{`echo "$(gcloud secrets versions access latest --secret=foo)" | sha256sum`, "allow"},
		{"gcloud secrets versions access latest --secret=foo && echo done", "deny"},
		{"gcloud secrets versions access latest --secret=foo || echo failed", "deny"},
		{"gcloud secrets versions access latest --secret=foo; echo done", "deny"},
		{"x=$(rm -rf /)", "deny"},
		{"rm -rf /", "deny"},
		{"gcloud secrets list", "allow"},
		{"gcloud secrets describe my-secret", "allow"},
		{"gcloud config list", "allow"},
		{"if true; then gcloud secrets versions access latest --secret=foo; fi", "deny"},
		{"if true; then x=$(gcloud secrets versions access latest --secret=foo); fi", "allow"},
	}

	for _, tt := range tests {
		t.Run(tt.cmd, func(t *testing.T) {
			input := hookInput{}
			input.ToolInput.Command = tt.cmd
			data, _ := json.Marshal(input)

			r, w, _ := os.Pipe()
			_, _ = w.Write(data)
			_ = w.Close()
			origStdin := os.Stdin
			os.Stdin = r
			defer func() { os.Stdin = origStdin }()

			log := devlogs.NewLogger("test")
			got := run(log)

			var action string
			switch {
			case got == nil:
				action = "abstain"
			case got.Action == "allow":
				action = "allow"
			case got.Action == "deny":
				action = "deny"
			}

			if action != tt.want {
				t.Errorf("run(%q) = %s, want %s", tt.cmd, action, tt.want)
			}
		})
	}
}

func parseWords(s string) []*syntax.Word {
	parser := syntax.NewParser(syntax.Variant(syntax.LangBash))
	file, err := parser.Parse(strings.NewReader(s), "")
	if err != nil || len(file.Stmts) == 0 {
		return nil
	}
	call, ok := file.Stmts[0].Cmd.(*syntax.CallExpr)
	if !ok || len(call.Args) == 0 {
		return nil
	}
	return call.Args[1:]
}

func TestParseSSHArgs(t *testing.T) {
	tests := []struct {
		input   string
		wantCmd string
		wantOK  bool
	}{
		{"ssh hermes git status", "git status", true},
		{"ssh hermes 'systemctl status foo'", "systemctl status foo", true},
		{"ssh -v hermes git status", "git status", true},
		{"ssh -vvv hermes git status", "git status", true},
		{"ssh -p 2222 hermes git status", "git status", true},
		{"ssh -p2222 hermes git status", "git status", true},
		{"ssh -o StrictHostKeyChecking=no hermes git", "git", true},
		{"ssh -oStrictHostKeyChecking=no hermes git", "git", true},
		{"ssh -i /tmp/key hermes git status", "git status", true},
		{"ssh -vp 2222 -i /tmp/key hermes git status", "git status", true},
		{"ssh -- hermes git status", "git status", true},
		{"ssh hermes", "", true},
		{"ssh -N hermes", "", true},
		{"ssh -v", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			args := parseWords(tt.input)
			got, ok := extractSSHRemoteCmd(args)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if got != tt.wantCmd {
				t.Errorf("cmd = %q, want %q", got, tt.wantCmd)
			}
		})
	}
}

func TestParseShellExecArgs(t *testing.T) {
	tests := []struct {
		input   string
		wantCmd string
		wantOK  bool
	}{
		{"bash -c 'git status'", "git status", true},
		{"bash -c 'cmd1; cmd2'", "cmd1; cmd2", true},
		{"bash -xc 'git status'", "git status", true},
		{"bash -x -e -c 'git status'", "git status", true},
		{"bash -o pipefail -c 'git status'", "git status", true},
		{"bash", "", true},
		{"bash script.sh", "", true},
		{"bash -x script.sh", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			args := parseWords(tt.input)
			got, ok := extractShellExecCmd(args)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if got != tt.wantCmd {
				t.Errorf("cmd = %q, want %q", got, tt.wantCmd)
			}
		})
	}
}

func TestExtractNixShellCmd(t *testing.T) {
	tests := []struct {
		input   string
		wantCmd string
		wantOK  bool
	}{
		{"nix-shell --run 'git status'", "git status", true},
		{"nix-shell -p git --run 'git status'", "git status", true},
		{"nix-shell --pure --run 'git log'", "git log", true},
		{"nix-shell --command 'git status'", "git status", true},
		{"nix-shell", "", true},
		{"nix-shell -p git", "", true},
		{"nix-shell default.nix", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			args := parseWords(tt.input)
			got, ok := extractNixShellCmd(args)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if got != tt.wantCmd {
				t.Errorf("cmd = %q, want %q", got, tt.wantCmd)
			}
		})
	}
}

func TestExtractNixCmd(t *testing.T) {
	tests := []struct {
		input   string
		wantCmd string
		wantOK  bool
	}{
		{"nix develop --command git status", "git status", true},
		{"nix develop .#foo --command git log --oneline", "git log --oneline", true},
		{"nix shell nixpkgs#git --command git status", "git status", true},
		{"nix develop", "", true},
		{"nix shell nixpkgs#git", "", true},
		{"nix build .#foo", "", true},
		{"nix flake show", "", true},
	}

	for _, tt := range tests {
		t.Run(tt.input, func(t *testing.T) {
			args := parseWords(tt.input)
			got, ok := extractNixCmd(args)
			if ok != tt.wantOK {
				t.Fatalf("ok = %v, want %v", ok, tt.wantOK)
			}
			if got != tt.wantCmd {
				t.Errorf("cmd = %q, want %q", got, tt.wantCmd)
			}
		})
	}
}
