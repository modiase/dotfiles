# shellcheck shell=bash
if [[ -z "$TMUX" ]]; then exit 1; fi

panes=$(tmux list-panes -F '#{pane_id} #{pane_current_command} #{pane_current_path}' | grep -i nvim) || true
if [[ -z "$panes" ]]; then exit 1; fi

count=$(echo "$panes" | wc -l | tr -d ' ')
if [[ "$count" -eq 1 ]]; then
    selected="$panes"
elif command -v gum >/dev/null 2>&1; then
    selected=$(echo "$panes" | gum choose --header "Select neovim pane")
    if [[ -z "$selected" ]]; then exit 1; fi
else
    selected=$(echo "$panes" | head -n 1)
fi

target_pane=$(echo "$selected" | cut -d' ' -f1)
socket=$(tmux show-environment "NVIM_$target_pane" 2>/dev/null | cut -d= -f2) || true
if [[ -z "$socket" || ! -e "$socket" ]]; then exit 1; fi

echo "TARGET_PANE=$target_pane"
echo "NVIM_SOCKET=$socket"
