# devlogs

TUI for streaming and filtering structured log messages from all IDE
components.

## Log format

```
component{instance}(@window): message
```

- **component** — the log source (e.g. `claude`, `gemini`, `nvim-mcp`)
- **instance** — read from `$DEVLOGS_INSTANCE` at log time. Falls back to
  `"-"` when unset.
- **window** — tmux window ID, auto-detected by devlogs-lib

## Common usage

```bash
devlogs                                    # live TUI, current window
devlogs -w -1                              # live TUI, all windows
devlogs --plain --history 5m | grep <id>   # filter to one session
pgrep -fa "wrapper-id <id>"               # find all session processes
```

## TUI keybindings

| Key       | Action                              |
|-----------|-------------------------------------|
| `/`       | Filter by substring                 |
| `a`       | Toggle window filter (all/current)  |
| `l`       | Cycle log level                     |
| `H`       | Cycle history duration              |
| `c`       | Clear entries                       |
| `f`       | Toggle follow mode                  |
| `q`       | Quit                                |
