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
    case "$level" in
        debug | info | warning | error) shift ;;
        *) level="info" ;;
    esac
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    local priority="user.$level"
    # macOS unified logging drops user.debug from history; promote so log show works
    if [[ "$level" == "debug" ]]; then priority="user.info"; fi
    logger -t devlogs -p "$priority" "[devlogs] ${level^^} ${_DEVLOGS_COMPONENT}{${_DEVLOGS_INSTANCE}}${win}: $*"
}
