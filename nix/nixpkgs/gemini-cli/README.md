# gemini-cli

Nix wrapper around the Gemini CLI binary that adds IDE integration, hooks,
plan review, and an editor wrapper.

## Wrapper output

The `gemini` binary:

1. Generates a `WRAPPER_ID` UUID
2. Sets `EDITOR=gemini-editor` so the agent opens files in Neovim
3. Discovers an existing Neovim session or picks an ephemeral port for the IDE
   bridge
4. Launches `gemini-nvim-ide-bridge` as a background HTTP server
5. Exports `DEVLOGS_INSTANCE=$WRAPPER_ID`

## Hook events

| Event          | Matcher          | What it does                                                       |
| -------------- | ---------------- | ------------------------------------------------------------------ |
| `SessionStart` | `startup`        | `init` — returns `AGENTS.md` as `additionalContext`                |
| `BeforeAgent`  | —                | `before-agent` — injects mandatory reasoning constraints each turn |
| `BeforeTool`   | `write_file`     | `before-plan-write` — injects planning context for plan files only |
| `BeforeTool`   | `exit_plan_mode` | `close-plan` — cleanup stub                                        |
| `AfterTool`    | `write_file`     | `gemini-nvim-plan` — opens plan in Neovim, spawns responder        |
| `AfterTool`    | `exit_plan_mode` | `after-plan` — injects post-approval context (TODO creation)       |
| `AfterAgent`   | —                | `stop` — sends desktop notification via `ding`                     |
| `Notification` | `*`              | `permission` — interactive Allow/Show dialog via `ding`            |

## Plan review

Triggered by `AfterTool(write_file)` when the written path matches
`*/.gemini/*/plans/*.md`. The `gemini-nvim-plan` script extracts the plan
path from stdin and delegates to
[agents-plan-responder](../agents-plan-responder/README.md).

## IDE bridge

`gemini-nvim-ide-bridge` is a Go HTTP server providing editor context to the
agent via MCP-over-HTTP:

- `GET /sse` — Server-Sent Events keep-alive, announces the `/mcp` endpoint
- `POST /mcp` — JSON-RPC tools: `get_active_editor_context`, `open_file`,
  `openDiff`, `closeDiff`, `get_diagnostics`

The bridge writes a discovery JSON to `/tmp/gemini/ide/` for the agent to
locate, communicates with Neovim via RPC, and exits when its parent process
dies (polls `getppid()` every 2s).
