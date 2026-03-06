---
name: claude-settings
description: Use when modifying Claude Code settings (permissions, hooks, theme), writing skills, or adding CLAUDE.md instructions.
---

# Claude Code Settings Management

## Cardinal Rule

**NEVER edit `~/.claude/settings.json` directly.** It is a symlink into the Nix store and will be overwritten on the next activation. All changes must be made in this repo, specifically in `nix/nixpkgs/claude-code/settings.nix`.

`~/.claude/settings.local.json` is the only file that can be edited directly — use it for temporary overrides that should not be committed.

## Scope: User-wide vs Repo-scoped

| Scope | Location | Managed by |
|-------|----------|------------|
| User-wide settings (`~/.claude/settings.json`) | `nix/nixpkgs/claude-code/settings.nix` | Nix / home-manager |
| User-wide skills (`~/.claude/skills/`) | `nix/nixpkgs/agents-config/skills/` | Nix / home-manager (symlinked) |
| Repo-scoped skills (this repo only) | `.agents/skills/` | Git (plain markdown, no Nix) |

User-wide changes require Nix rebuilds via `bin/activate`. Repo-scoped skills take effect immediately.

If you are unsure whether a requested change should be user-wide (Nix-managed) or repo-scoped (`.agents/`), **ask the user** before proceeding.

## File Locations

| File | Role |
|------|------|
| `nix/nixpkgs/claude-code/settings.nix` | Source of truth — permissions, hooks, theme as a Nix attrset |
| `nix/nixpkgs/claude-code/default.nix` | Imports settings.nix, builds hook scripts, converts to JSON, wires home-manager |
| `nix/nixpkgs/claude-code/scripts/` | Hook scripts (one `.sh` per hook, built with `writeShellApplication`) |

## Nix to JSON Flow

```
settings.nix  ──import──▶  default.nix  ──lib.recursiveUpdate──▶  merged attrset
                                         ──builtins.toJSON──▶  writeText "claude-settings.json"
                                         ──home.file──▶  ~/.claude/settings.json (symlink)
```

1. `settings.nix` returns an attrset parameterised by `{ hookBin, devnullHookBin }`
2. `default.nix` imports it, merges the `PostToolUse` hook via `lib.recursiveUpdate`
3. The merged attrset is serialised to JSON with `pkgs.writeText`
4. Home-manager symlinks the result to `~/.claude/settings.json`

## Permission Rules

### Syntax

Rules are strings in `permissions.allow` or `permissions.deny`:

```
Tool(pattern)
```

| Tool | Pattern format | Example |
|------|---------------|---------|
| `Bash` | `command-prefix:*` — matches commands starting with the prefix | `"Bash(git status:*)"` |
| `Read` | glob path | `"Read(~/.ssh/*)"` |
| `Edit` | glob path | `"Edit(/tmp/*)"` |
| `WebFetch` | `domain:hostname` | `"WebFetch(domain:github.com)"` |
| MCP tools | `mcp__server__*` — wildcard on tool name | `"mcp__nixos__*"` |

The `:*` suffix on Bash rules matches any arguments after the prefix. Without it, only the exact command matches.

### Deny rules

Deny rules take precedence. Current deny rules block:

- Secret access — `gcloud secrets versions access`, `secrets get`
- In-place sed — `sed -i`, `sed --in-place` (use the Edit tool instead)
- SSH keys — `Read(~/.ssh/*)`

### Allow rules

Allow rules auto-approve without prompting. Organised by category:

- **Nix** — `nix eval`, `nix build`, `nix flake show/metadata/check`, `nix-instantiate`, `nix-build`, `nixos-option`
- **Git (read-only)** — `status`, `log`, `diff`, `show`, `branch`, `remote`, `rev-parse`, `ls-files`, `ls-tree`, `stash list`, `tag`, `describe`, `shortlog`, `config`, `blame`, `reflog`, `worktree list`; also `git -C <path>` variants
- **Filesystem** — `ls`, `cat`, `head`, `tail`, `wc`, `stat`, `realpath`, `dirname`, `basename`, `readlink`, `fd`, `rg`, `find`, `grep`, `tree`, `eza`, `od`, `sed` (non-in-place), `echo`, `printf`
- **Build/lint** — `go build/vet/test/list/mod tidy`, `make`, `pre-commit`, `jq`, `yq`, `curl`, `wget`
- **GCloud (read-only)** — `logging read/list/describe`, `compute instances list/describe`, `projects describe`, `config list`, `storage ls`
- **System inspection** — `systemctl status/show/list-*`, `journalctl`, `which`, `type`, `file`, `uname`, `hostname`, `env`, `printenv`, `id`, `whoami`, `df`, `du`, `free`, `uptime`, `ps`, `pgrep`, `lsof`
- **MCP** — all `mcp__exa__*` and `mcp__nixos__*` tools
- **WebFetch domains** — documentation sites (nixos.org, github.com, docs.python.org, pkg.go.dev, etc.)

### Adding a new rule

Edit `nix/nixpkgs/claude-code/settings.nix`, add the string to the appropriate list:

```nix
permissions.allow = [
  # existing rules ...
  "Bash(terraform plan:*)"
];
```

## Hooks

Hooks run shell commands in response to Claude Code lifecycle events.

### Hook types

| Event | When it fires | Current use |
|-------|--------------|-------------|
| `PreToolUse` | Before a tool executes | `allow-devnull` — auto-allows Bash commands that only redirect to `/dev/null` |
| `PostToolUse` | After a tool executes | `nvim-plan` — opens plan files in neovim when `ExitPlanMode` fires |
| `Stop` | Agent stops (task complete or interrupted) | `claude-hook stop` — sends desktop/ntfy notification |
| `PermissionRequest` | User is prompted for permission | `claude-hook permission` — sends notification so user knows input is needed |

### Hook structure in settings.nix

```nix
hooks = {
  PreToolUse = [
    {
      matcher = "Bash";
      hooks = [
        {
          type = "command";
          command = "/nix/store/.../bin/script-name";
        }
      ];
    }
  ];
};
```

- `matcher` — tool name string or `"*"` to match all tools
- `type` — always `"command"`
- `command` — absolute path to the executable (use Nix store paths)

### Adding a new hook

1. Create `nix/nixpkgs/claude-code/scripts/my-hook.sh` with the script body
2. In `default.nix`, build it with `writeShellApplication`:
   ```nix
   myHookScript = pkgs.writeShellApplication {
     name = "my-hook";
     runtimeInputs = [ pkgs.jq ];
     text = builtins.readFile ./scripts/my-hook.sh;
   };
   ```
3. Pass the store path into `settings.nix` or merge it in `default.nix` via `lib.recursiveUpdate`
4. Hooks receive context on stdin as JSON (tool name, input, transcript path, etc.)

### Hook input

Hooks receive a JSON object on stdin containing fields like:
- `tool_name` — the tool being invoked
- `tool_input` — the tool's parameters (e.g., `tool_input.command` for Bash)
- `transcript_path` — path to the current conversation transcript

A `PreToolUse` hook can emit `{"permissionDecision":"allow"}` to auto-approve.

## Other Settings

```nix
{
  theme = "ANSI Dark";
  alwaysThinkingEnabled = true;
  enabledPlugins = {
    "gopls-lsp@claude-plugins-official" = true;
  };
}
```

## Applying Changes

After editing files in `nix/nixpkgs/claude-code/`, run `bin/activate` to rebuild and symlink the new settings. The change takes effect for the next Claude Code session (restart Claude Code if already running).
