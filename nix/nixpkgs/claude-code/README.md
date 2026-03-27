# claude-code

Nix wrapper around the Claude Code binary that adds IDE integration, hooks,
and plan review.

## Wrapper output

The `claude` binary:

1. Generates a `WRAPPER_ID` UUID
2. Detects an existing Neovim session via IDE lock files in `~/.claude/ide/`
3. Generates `AGENTS.md` and passes it to the real binary with
   `--append-system-prompt`
4. Exports `DEVLOGS_INSTANCE=$WRAPPER_ID`

## Hook events

| Event               | Matcher             | What it does                                           |
|---------------------|---------------------|--------------------------------------------------------|
| `SessionStart`      | —                   | `init` — logs session start                            |
| `Stop`              | —                   | `stop` — sends desktop notification via `ding`         |
| `PermissionRequest` | —                   | `permission` — interactive Allow/Show dialog via `ding`|
| `PreToolUse`        | `Bash`              | `allow-shellcommand` — pre-flight permission check     |
| `PreToolUse`        | `ExitPlanMode`      | `nvim-plan` — opens plan in Neovim, spawns responder   |
| `PostToolUse`       | `ExitPlanMode`      | `close-plan` — cleanup stub                            |

## Plan review

Triggered by `PreToolUse(ExitPlanMode)`. The `nvim-plan` script finds the
latest plan in `~/.claude/plans/` and delegates to
[agents-plan-responder](../agents-plan-responder/README.md).
