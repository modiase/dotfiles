---
name: activate
description: Apply NixOS/darwin/home-manager configuration changes. Use when deploying system configurations.
allowed-tools: Bash(bin/activate*)
---

# System Activation

Use `bin/activate` to apply configuration changes. Never call darwin-rebuild, nixos-rebuild, or home-manager directly.

## Commands

| Command | Description |
|---------|-------------|
| `bin/activate` | Activate current repo state on local machine |
| `bin/activate deploy` | Deploy origin/main to localhost via worktree |
| `bin/activate deploy <host>` | Deploy origin/main to remote host via SSH |
| `bin/activate deploy all` | Deploy to all hosts with `manageRemotely = true` |
| `bin/activate show` | Show activation status (hashes for origin/main, worktree, system, home) |
| `bin/activate show <host>` | Show activation status on remote host |

## Options

Global flags **must come BEFORE** subcommand:

| Flag | Description |
|------|-------------|
| `-l LEVEL` | Log level: 1=errors, 2=normal (default), 3=verbose, 4+=debug |
| `-c CORES` | Max cores for parallel builds (default: ncpu - 1) |
| `-t TIMEOUT` | Lock timeout in minutes (default: 30) |
| `-s SYSTEM` | Override system name for config selection |

## When to Use Each

| Use Case | Command |
|----------|---------|
| Testing working tree changes | `bin/activate` |
| Deploying tested changes to remote | `bin/activate deploy <host>` |
| Batch update all managed hosts | `bin/activate deploy all` |
| Check sync status | `bin/activate show [host]` |

## Key Constraints

- **Flag order matters**: `bin/activate -l 3 deploy hestia` (correct), NOT `bin/activate deploy -l 3 hestia`
- **deploy uses origin/main**: Always resets worktree to origin/main, never uses working tree
- **Lock prevents concurrent runs**: If hung, check if another activation is running
- **Git-crypt must be unlocked**: Fails with clear error if not

## Debugging

Check logs before claiming "nothing happened":
- **macOS**: `~/Library/Logs/dotfiles-activate.log`
- **Linux**: `journalctl -u dotfiles-activate`

## Important

- **Do NOT activate without explicit user request**
- Remote hosts must have passwordless SSH configured
- `deploy all` waits for ALL hosts - fails if any fails

## Task

$ARGUMENTS
