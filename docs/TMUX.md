# tmux Scoping Behaviour

## `$TMUX` Environment Variable

The `$TMUX` variable encodes session context as `socket,session_id,window_index`:

```
/tmp/tmux-local,42595,0
```

Subprocesses inheriting `$TMUX` can run tmux commands with full context of the originating session and window.

## Command Scoping

### `tmux list-panes` — Window-scoped

Without `-a`, lists only panes in the **current window** (determined by `$TMUX`):

```bash
tmux list-panes -F '#{pane_id} #{pane_current_command}'
# %1 nvim
# %3 fish
```

With `-a`, lists all panes across all windows:

```bash
tmux list-panes -a -F '#{window_index}:#{pane_id} #{pane_current_command}'
# 0:%1 nvim
# 0:%3 fish
# 1:%6 nvim
# 1:%7 fish
```

### `tmux show-environment` — Session-scoped

Shows environment variables for the entire session, not window-specific:

```bash
tmux show-environment | grep NVIM
# NVIM_%1=/tmp/nvim.12345.0
# NVIM_%6=/tmp/nvim.67890.0
```

## Pattern: Window-Isolated Lookup

To find a resource in the current window using session-scoped storage:

1. Use `list-panes` (window-scoped) to find candidate pane IDs
2. Use `show-environment` with the pane ID as key

Pane IDs are unique across the session, so session-scoped storage keyed by pane ID provides correct isolation when combined with window-scoped discovery.
