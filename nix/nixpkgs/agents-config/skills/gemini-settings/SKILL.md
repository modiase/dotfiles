---
name: gemini-settings
description: How Gemini CLI settings are managed via Nix. Use when modifying permissions, hooks, or context.
---

# Gemini CLI Settings Management

Settings are Nix-managed. Do NOT edit `~/.gemini/settings.json` or `~/.gemini/policies/managed.toml` directly — they are symlinks to the Nix store and will be overwritten on activation.

## Key Files

| File | Purpose |
|------|---------|
| `nix/nixpkgs/gemini-cli/settings.nix` | Hooks, context file names -> JSON |
| `nix/nixpkgs/gemini-cli/policies.nix` | Permission allow/deny rules -> TOML |
| `nix/nixpkgs/gemini-cli/default.nix` | Builds scripts, generates config, symlinks |
| `nix/nixpkgs/gemini-cli/scripts/` | Hook scripts via `writeShellApplication` |

## Flow

1. `settings.nix` defines hooks and context as a Nix attribute set
2. `policies.nix` defines permission rules as a list of attrsets
3. `default.nix` converts settings to JSON, policies to TOML via `pkgs.formats.toml`
4. Home-manager symlinks results to `~/.gemini/settings.json` and `~/.gemini/policies/managed.toml`

## Adding Permissions

Add entries to `policies.nix` using the helper functions:

```nix
# Shell command by prefix
shell "command-prefix"

# Shell command by regex
shellRegex "pattern"

# Other tool types
{ toolName = "tool_name"; }
```

Rules are grouped into `allow 100 [...]` (priority 100) and `deny 900 [...]` (priority 900). Higher priority wins.

## Adding Hooks

For simple hooks, add to the `hooks` attribute in `settings.nix`. For hooks needing runtime dependencies, create a script in `scripts/`, build with `writeShellApplication` in `default.nix`, and reference the store path.
