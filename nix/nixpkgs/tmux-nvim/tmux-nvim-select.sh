# shellcheck shell=bash
if [[ -z "$TMUX" ]]; then exit 1; fi

_log_level="info"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -qq)
            _log_level=""
            shift
            ;;
        -q)
            _log_level="debug"
            shift
            ;;
        *) shift ;;
    esac
done

_clog() {
    if [[ -n "$_log_level" ]]; then clog "$_log_level" "$@"; fi
}

caller_window=$(tmux display-message -t "${TMUX_PANE:-}" -p '#{window_id}' 2>/dev/null) || true
if [[ -z "$caller_window" ]]; then
    clog error "can't resolve window pane=${TMUX_PANE:-unset}"
    exit 1
fi
clog debug "caller window=$caller_window pane=${TMUX_PANE:-}"

panes=$(tmux list-panes -t "$caller_window" -F '#{pane_id} #{pane_current_command} #{pane_current_path}' | grep -i nvim) || true
if [[ -z "$panes" ]]; then
    _clog "no nvim panes found window=$caller_window"
    exit 1
fi

count=$(echo "$panes" | wc -l | tr -d ' ')
if [[ "$count" -eq 1 ]]; then
    selected="$panes"
elif [[ -t 0 ]] && command -v gum >/dev/null 2>&1; then
    selected=$(echo "$panes" | gum choose --header "Select neovim pane")
    if [[ -z "$selected" ]]; then exit 1; fi
else
    selected=$(echo "$panes" | head -n 1)
fi

target_pane=$(echo "$selected" | cut -d' ' -f1)
socket=$(tmux show-environment "NVIM_$target_pane" 2>/dev/null | cut -d= -f2) || true
if [[ -z "$socket" || ! -e "$socket" ]]; then
    _clog "invalid socket pane=$target_pane"
    exit 1
fi

clog debug "resolved pane=$target_pane socket=$socket"
echo "TARGET_PANE=$target_pane"
echo "NVIM_SOCKET=$socket"
