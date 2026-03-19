# IDE Integration

Three AI agents — Claude Code, Gemini CLI, and opencode — share a single
Neovim instance running in tmux. Each agent runs in its own tmux pane and
connects to Neovim through MCP or HTTP bridges. A shell wrapper around each
agent generates a unique `WRAPPER_ID` that tags every spawned process for
traceability.

## Wrappers

Each agent wrapper (`claude`, `gemini`):

1. Generates a `WRAPPER_ID` UUID
2. Discovers the Neovim socket via `tmux-nvim-select`
3. Sets up IDE integration (SSE port for Claude, HTTP bridge for Gemini)
4. Launches the underlying agent binary

The wrapper ID reaches child processes through two mechanisms:

- **Explicit flag** (`--wrapper-id`): for processes the wrapper or its hooks
  spawn directly (plan responder, IDE bridge, MCP proxy)
- **Environment variable** (`$WRAPPER_ID`): inherited by processes the agent
  CLI spawns (hooks, MCP servers) where we cannot control the invocation

Both mechanisms ensure the ID appears in process argv for `pgrep`. The ID is
also embedded in `DEVLOGS_COMPONENT` (e.g. `claude[<id>]`) so every log line
carries it automatically.

opencode uses a third-party wrapper with no `WRAPPER_ID` integration. Its
Neovim plugin (`opencode.nvim`) handles plan display via a file watcher
instead of the FIFO-based system described below.

## Neovim Socket Discovery

`tmux-nvim-select` finds Neovim by scanning tmux panes in the caller's
window for processes matching `nvim`. It reads the socket path from the tmux
environment variable `NVIM_<pane_id>` and exports `NVIM_SOCKET` and
`TARGET_PANE`. When multiple Neovim panes exist, it prompts with `gum choose`
if a TTY is available.

## MCP Server (nvim-mcp)

A Python JSON-RPC proxy (`nvim-mcp-proxy.py`) wraps the `nvim-mcp` Rust
binary to add automatic socket discovery:

- On startup, calls `tmux-nvim-select` to find Neovim
- Intercepts `connect(target="auto")` calls and substitutes the real socket
- Polls socket health every 3s and reconnects when sockets disappear
- Strips `--wrapper-id` from argv before forwarding to the child process

Configured as a shared MCP server available to all agents:

```nix
mcpServers.nvim = { type = "stdio"; command = "nvim-mcp"; };
```

## Gemini IDE Bridge

An HTTP server (`gemini-nvim-ide-bridge`) launched by the Gemini wrapper
provides editor context to the agent:

| Endpoint | Purpose                                                      |
| -------- | ------------------------------------------------------------ |
| `/sse`   | Server-Sent Events keep-alive, announces `/mcp`             |
| `/mcp`   | JSON-RPC tools: `get_active_editor_context`, `open_file`, `openDiff`, `closeDiff` |

The bridge communicates with Neovim via RPC, writes a discovery JSON to
`/tmp/gemini/ide/` for the agent to locate, and exits when its parent process
dies.

Claude Code uses a different mechanism: it reads IDE lock files from
`~/.claude/ide/*.lock` to find its SSE port.

## Plan Review

When an agent produces a plan:

1. A hook triggers the `nvim-plan` script
2. The script creates a FIFO and spawns `agents-plan-responder` in the
   background
3. Neovim opens the plan in a new tab with keymaps (accept, reject, comment)
4. The responder blocks on the FIFO indefinitely until the user acts
5. User presses a keymap — Lua writes the chosen action to the FIFO
6. The responder reads the action and sends the corresponding keystroke to
   the agent's tmux pane

Each invocation kills any existing responder for the same wrapper via a PID
file, preventing zombie FD leaks.

### Agent differences

|                 | Claude                      | Gemini                              | opencode                         |
| --------------- | --------------------------- | ----------------------------------- | -------------------------------- |
| Hook trigger    | `PreToolUse(ExitPlanMode)`  | `AfterTool(write_file)`             | File watcher (`.opencode/plans/`) |
| Plan location   | `~/.claude/plans/`          | `~/.gemini/<session>/plans/`        | `.opencode/plans/` (local)       |
| Dialog pattern  | `manually approve edits`    | `Ready to start implementation`     | N/A                              |
| Responder       | FIFO + plan-responder       | FIFO + plan-responder               | None (Neovim plugin)             |
| PID file        | `/tmp/plan-responder-<wrapper-id>.pid` | `<session-dir>/plan-responder.pid` | N/A                              |

## Hooks

Hooks are shell scripts invoked by the agent CLI at lifecycle points. All
receive `--wrapper-id` in their command string (after any positional event
argument) and explicitly parse it.

| Agent  | Events                                                                  |
| ------ | ----------------------------------------------------------------------- |
| Claude | `init`, `stop`, `permission`                                            |
| Gemini | `init`, `before-agent`, `before-plan-write`, `after-plan`, `stop`, `permission` |

Gemini's `before-agent` hook injects mandatory reasoning constraints each
turn. Its `init` hook returns the generated `AGENTS.md` as additional context.
Claude's `init` hook injects `AGENTS.md` via the `--append-system-prompt`
flag instead.

## Process Tree

```
claude (wrapper)
├── claude-code binary
│   ├── nvim-mcp --wrapper-id <id>          (MCP server, stdio)
│   │   └── nvim-mcp (Rust)
│   ├── allow-shellcommand --wrapper-id <id> (Bash hook)
│   ├── claude-hook init --wrapper-id <id>
│   ├── nvim-plan --wrapper-id <id>          (plan hook)
│   │   └── agents-plan-responder --wrapper-id <id>
│   └── close-plan --wrapper-id <id>

gemini (wrapper)
├── gemini-nvim-ide-bridge -wrapper-id <id>  (background HTTP server)
├── gemini-cli binary
│   ├── nvim-mcp --wrapper-id <id>          (MCP server, stdio)
│   │   └── nvim-mcp (Rust)
│   ├── gemini-hook init --wrapper-id <id>
│   ├── gemini-nvim-plan --wrapper-id <id>   (plan hook)
│   │   └── agents-plan-responder --wrapper-id <id>
│   └── gemini-close-plan --wrapper-id <id>
```

## Observability

All processes log through devlogs. Component names follow the format
`name[wrapper-id](@window)`.

```bash
devlogs                                         # live TUI
devlogs --plain --history 5m | grep <id>        # filter to one session
pgrep -fa "wrapper-id <id>"                     # find all session processes
```

## File Locations

| Path                                 | Purpose                    |
| ------------------------------------ | -------------------------- |
| `~/.claude/plans/*.md`               | Claude plan files          |
| `~/.gemini/<session>/plans/*.md`     | Gemini plan files          |
| `.opencode/plans/*.md`               | opencode plans (local)     |
| `~/.agents/AGENTS.md`                | Shared agent instructions  |
| `~/.agents/skills/`                  | Shared skill definitions   |
| `/tmp/nvim-plan-<uuid>.fifo`         | Plan responder FIFO        |
| `/tmp/plan-responder-<wrapper-id>.pid` | Responder PID (Claude)     |
| `/tmp/gemini/ide/*.json`             | IDE bridge discovery       |
| `~/.claude/ide/*.lock`               | Claude IDE lock files      |
