---
name: claude-settings
description: How Claude Code settings are managed via Nix. Use when modifying permissions, hooks, or theme.
---

# Claude Code Settings Management

Settings are Nix-managed. Do NOT edit `~/.claude/settings.json` directly — it is a symlink to the Nix store and will be overwritten on activation.

## Key Files

| File | Purpose |
|------|---------|
| `nix/nixpkgs/claude-code/settings.nix` | Permissions, hooks, theme → JSON |
| `nix/nixpkgs/claude-code/default.nix` | Builds scripts, wraps binary, symlinks settings |
| `nix/nixpkgs/claude-code/scripts/` | Hook scripts via `writeShellApplication` |

## Flow

1. `settings.nix` defines the settings as a Nix attribute set
2. `default.nix` imports it, merges additional hooks, converts to JSON via `writeText`
3. Home-manager symlinks the result to `~/.claude/settings.json` (or `$CLAUDE_CONFIG_DIR/settings.json`)

## Adding Permissions

Add entries to `permissions.allow` or `permissions.deny` in `settings.nix`:
```nix
"Bash(command-prefix:*)"
```

## Adding Hooks

For simple hooks, add to the `hooks` attribute in `settings.nix`. For hooks needing runtime dependencies, create a script in `scripts/`, build with `writeShellApplication` in `default.nix`, and reference the store path.
