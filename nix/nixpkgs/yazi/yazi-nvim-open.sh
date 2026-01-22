[ -z "$TMUX" ] && exec nvim "$@"

TARGET_PANE=$(tmux list-panes -F '#{pane_id} #{pane_current_command}' | grep -i nvim | head -n 1 | cut -d' ' -f1)
[ -z "$TARGET_PANE" ] && exec nvim "$@"

NVIM_LISTEN_ADDRESS=$(tmux show-environment "NVIM_$TARGET_PANE" 2>/dev/null | cut -d= -f2)
export NVIM_LISTEN_ADDRESS

[ -z "$NVIM_LISTEN_ADDRESS" ] || [ ! -e "$NVIM_LISTEN_ADDRESS" ] && exec nvim "$@"

nvr --remote-tab "$@"
tmux select-pane -t "$TARGET_PANE"
