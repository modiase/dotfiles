#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: ding [OPTIONS]

Notification tool that adapts to context (tmux, focus state, local/remote).

Options:
  --force         Always play sound/alert (skip focus detection)
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
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage ;;
        --debug)
            debug=1
            shift
            ;;
        --force)
            force=1
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

ghostty_is_focused() {
    local frontmost
    frontmost=$(osascript -e 'tell application "System Events" to name of (first process whose frontmost is true)')
    [[ "${frontmost,,}" == "ghostty" ]]
}

tmux_window_is_active() {
    [[ -z "${TMUX_PANE:-}" ]] && return 0
    local pane_window active_window
    pane_window=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || return 1
    active_window=$(tmux display-message -p '#{window_id}' 2>/dev/null) || return 1
    [[ "$pane_window" == "$active_window" ]]
}

send_bell() {
    if [[ -n "${TMUX_PANE:-}" ]]; then
        local tty_path
        tty_path=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null) || true
        [[ -n "$tty_path" ]] && printf '\a' >"$tty_path" 2>/dev/null || true
    else
        printf '\a'
    fi
}

send_alert() {
    local alert_title="$1" msg="$2"
    afplay /System/Library/Sounds/Glass.aiff &
    [[ -n "$msg" ]] && osascript -e "display alert \"$alert_title\" message \"$msg\"" >/dev/null &
}

if [[ "$mode" == "local" ]]; then
    if ! command -v osascript &>/dev/null; then
        echo "Error: --local requires macOS (osascript not found)" >&2
        exit 1
    fi

    alert_title="${title:-Notification}"
    log_debug "--- ding invoked ---"

    if [[ $force -eq 0 ]] && ghostty_is_focused && tmux_window_is_active; then
        log_debug "Caller focused, bell only"
        send_bell
    else
        log_debug "Sound + alert"
        send_alert "$alert_title" "$message"
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
