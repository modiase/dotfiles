# tmux-nvim

Shell script (`tmux-nvim-select`) that discovers Neovim instances running in
the current tmux window and exports their socket paths.

## Socket discovery

1. Resolves the caller's tmux window from `$TMUX_PANE`
2. Lists all panes in that window via `tmux list-panes`
3. Filters for panes whose current command matches `nvim`

## `NVIM_<pane_id>` convention

Each Neovim instance stores its socket path in a tmux session-scoped
environment variable named `NVIM_<pane_id>` (e.g. `NVIM_%3`). The script
reads this with `tmux show-environment` to resolve the socket.

## Multi-nvim selection

When multiple Neovim panes exist in the window:

- **Interactive TTY available**: prompts with `gum choose`
- **Non-interactive**: falls back to the first pane

## Exported variables

The script outputs key-value pairs for `eval`:

- `NVIM_SOCKET` — the resolved Neovim socket path
- `TARGET_PANE` — the tmux pane ID running Neovim

Consumers typically source it as `eval "$(tmux-nvim-select)"`.
