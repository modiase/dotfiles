# shellcheck shell=bash
_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

_DEVLOGS_COMPONENT="${DEVLOGS_COMPONENT:-unknown}"
_DEVLOGS_INSTANCE="${DEVLOGS_INSTANCE:--}"

devlogs_init() {
    _DEVLOGS_COMPONENT="${1:-${DEVLOGS_COMPONENT:-unknown}}"
    _DEVLOGS_INSTANCE="${DEVLOGS_INSTANCE:--}"
}

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} ${_DEVLOGS_COMPONENT}{${_DEVLOGS_INSTANCE}}${win}: $*"
}
