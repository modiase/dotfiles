# agents-plan-responder

Single-purpose IPC bridge that relays a user's plan decision from Neovim to
an agent's tmux pane via a named pipe.

## FIFO-based blocking pattern

The responder opens a FIFO (named pipe) for reading and blocks until a writer
appears. This avoids polling — the process sleeps indefinitely until the user
acts in Neovim. The FIFO guarantees single-write semantics: one reader, one
writer, one message.

## Flow

1. The agent's hook runs its `nvim-plan` script (see agent READMEs for
   triggers)
2. The script creates a FIFO at `/tmp/nvim-plan-<uuid>.fifo` and spawns
   `agents-plan-responder` via `setsid` (detached session leader)
3. Neovim opens the plan in a new tab with keymaps (accept, reject, comment)
   and stores the FIFO path in a window variable
4. The responder **blocks on FIFO open**
5. User presses a keymap — Neovim Lua writes the action string to the FIFO via
   a detached shell job
6. The responder reads the action, cleans up the FIFO, then polls the agent's
   tmux pane for the expected dialog pattern (up to 30s)
7. Once the pattern appears, it sends the corresponding keystroke to the pane

## PID file zombie prevention

Each `nvim-plan` invocation records the responder's PID. On the next
invocation, it kills the previous responder before spawning a new one. This
prevents accumulation when the user reviews multiple plans in one session.

## Agent differences

|                  | Claude                          | Gemini                              |
|------------------|---------------------------------|-------------------------------------|
| Hook trigger     | `PreToolUse(ExitPlanMode)`      | `AfterTool(write_file)`             |
| Plan location    | `~/.claude/plans/`              | `~/.gemini/<session>/plans/`        |
| Dialog pattern   | `manually approve edits`        | `Ready to start implementation`     |
| PID file         | `/tmp/plan-responder-<id>.pid`  | `<session-dir>/plan-responder.pid`  |
| Accept keys      | 1 (clear), 2 (auto), 3 (manual)| 1 (auto), 2 (manual)               |
| Reject key       | 4                               | 3                                   |
