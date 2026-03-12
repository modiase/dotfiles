# shellcheck shell=bash
cat >/dev/null

_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} close-plan${win}: $*"
}

eval "$(tmux-nvim-select 2>/dev/null)" || exit 0
if [[ -z "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim socket"
    exit 0
fi

clog info "closing socket=$NVIM_SOCKET"
nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.claude-plan').close()" 2>/dev/null || true
exit 0
