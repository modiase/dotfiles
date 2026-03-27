# IDE Integration

Three AI agents — Claude Code, Gemini CLI, and opencode — share a single
Neovim instance running in tmux. Each agent runs in its own tmux pane and
connects to Neovim through MCP or HTTP bridges.

Component READMEs cover implementation details:

- [claude-code](../nix/nixpkgs/claude-code/README.md) — wrapper, hooks, plan review
- [gemini-cli](../nix/nixpkgs/gemini-cli/README.md) — wrapper, hooks, IDE bridge, plan review
- [nvim-mcp-wrapper](../nix/nixpkgs/nvim-mcp-wrapper/README.md) — JSON-RPC proxy with auto-connect
- [agents-plan-responder](../nix/nixpkgs/agents-plan-responder/README.md) — FIFO-based plan approval
- [tmux-nvim](../nix/nixpkgs/tmux-nvim/README.md) — Neovim socket discovery
- [devlogs](../nix/nixpkgs/devlogs/README.md) — unified logging TUI

## Wrappers

Each agent wrapper generates a `WRAPPER_ID` UUID that tags every spawned
process for traceability. The ID reaches child processes through two mechanisms:

- **Explicit flag** (`--wrapper-id`): for processes the wrapper spawns directly
  (plan responder, IDE bridge, MCP proxy). Appears in `pgrep` output.
- **Environment variable** (`$WRAPPER_ID` / `$DEVLOGS_INSTANCE`): inherited by
  processes the agent CLI spawns (hooks, MCP servers) where we cannot control
  the invocation.

opencode uses a third-party wrapper with no `WRAPPER_ID` integration.

## Plan Review

Agent plan decisions flow through
[agents-plan-responder](../nix/nixpkgs/agents-plan-responder/README.md),
which decouples the agent from the editor.

opencode diverges: its Neovim plugin watches `.opencode/plans/` via a file
watcher and handles plan display directly, with no wrapper-id or FIFO.

## Hooks

Hooks bridge agent lifecycle events to Neovim and devlogs. All hooks receive
`--wrapper-id` and explicitly parse it.

Both Claude and Gemini inject `AGENTS.md` into the agent's context at
startup, through different mechanisms (see their READMEs).
