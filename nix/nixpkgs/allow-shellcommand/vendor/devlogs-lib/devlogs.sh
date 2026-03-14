# shellcheck shell=bash
_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} ${DEVLOGS_COMPONENT:-unknown}${win}: $*"
}
