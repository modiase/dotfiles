# shellcheck shell=bash
_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

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
    logger -t devlogs -p "$priority" "[devlogs] ${level^^} ${DEVLOGS_COMPONENT:-unknown}${win}: $*"
}
