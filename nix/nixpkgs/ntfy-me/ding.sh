#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: ding [OPTIONS]

Notification tool that adapts to context (tmux, focus state, local/remote).

Options:
  --local         Force local mode (macOS osascript)
  --remote        Force remote mode (ntfy-me)
  --title TEXT    Alert title (default: "Notification")
  -m, --message   Alert message body
  --debug         Log debug info to /tmp/ding-debug.log
  -h, --help      Show this help

Behaviour:
  Local mode (macOS):
    - Always plays a sound and sends bell to terminal
    - Shows modal alert dialog only if Ghostty is not focused
    - In tmux: bell triggers window flag via monitor-bell

  Remote mode (Linux/SSH):
    - Sends notification via ntfy-me
    - Prefixes hostname to title automatically
EOF
    exit 0
}

mode=""
title=""
message=""
debug=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage ;;
        --debug)
            debug=1
            shift
            ;;
        --remote)
            mode="remote"
            shift
            ;;
        --local)
            mode="local"
            shift
            ;;
        --title)
            title="$2"
            shift 2
            ;;
        --title=*)
            title="${1#--title=}"
            shift
            ;;
        -m | --message)
            message="$2"
            shift 2
            ;;
        --message=*)
            message="${1#--message=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *) shift ;;
    esac
done

log_debug() {
    [[ $debug -eq 1 ]] && echo "[$(date '+%H:%M:%S')] $*" >>/tmp/ding-debug.log || true
}

# Auto-detect: local if osascript available, remote otherwise
if [[ -z "$mode" ]]; then
    if command -v osascript &>/dev/null; then
        mode="local"
    else
        mode="remote"
    fi
fi

if [[ "$mode" == "local" ]]; then
    if ! command -v osascript &>/dev/null; then
        echo "Error: --local requires macOS (osascript not found)" >&2
        exit 1
    fi

    frontmost=$(osascript -e 'tell application "System Events" to name of (first process whose frontmost is true)')
    alert_title="${title:-Notification}"

    log_debug "--- ding invoked ---"
    log_debug "TMUX=${TMUX:-<unset>}"
    log_debug "frontmost=$frontmost"

    afplay /System/Library/Sounds/Glass.aiff &

    if [[ -n "${TMUX_PANE:-}" ]]; then
        tty_path=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null) || true
        [[ -n "$tty_path" ]] && printf '\a' >"$tty_path" 2>/dev/null || true
    fi

    if [[ "${frontmost,,}" != "ghostty" && -n "$message" ]]; then
        log_debug "showing alert (Ghostty not focused)"
        osascript -e "display alert \"$alert_title\" message \"$message\"" &
    fi
else
    if [[ -z "$message" ]]; then
        echo "Warning: --remote without --message does nothing" >&2
        exit 0
    fi

    alert_title="${title:-Notification}"
    host="${HOSTNAME:-$(hostname -s)}"
    alert_title="$host:$alert_title"

    ntfy-me --topic ding --title "$alert_title" "$message"
fi
