#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: ding [OPTIONS]

Notification tool that adapts to context (tmux, focus state, local/remote).

Options:
  -c, --command CMD       Run command, alert success/error based on exit code
  -f, --force-alert       Always play sound/alert (skip focus detection)
  -i, --title TEXT        Bold header in message body
  -m, --message TEXT      Message body text
  -R, --recipient HOST    Target recipient for remote (default: * for all)
  -t, --type TYPE         Alert type: success, warning, error, request
  -w, --window-title TEXT Notification window title (default: hostname)
  --local                 Force local mode (macOS)
  --remote                Force remote mode (ntfy-me)
  --debug                 Log debug info to /tmp/ding-debug.log
  -h, --help              Show this help

Behaviour:
  Local mode:
    - Always plays a sound and sends bell to terminal
    - Shows modal alert dialog only if Ghostty is not focused
    - In tmux: bell triggers window flag via monitor-bell

  Remote mode (over SSH):
    - Sends notification via ntfy-me
EOF
    exit 0
}

alert_type=""
command=""
message=""
mode=""
recipient="*"
title=""
window_title=""

debug=0
force=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage ;;
        --debug)
            debug=1
            shift
            ;;
        -f | --force-alert)
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
        -i | --title)
            title="$2"
            shift 2
            ;;
        --title=*)
            title="${1#--title=}"
            shift
            ;;
        -w | --window-title)
            window_title="$2"
            shift 2
            ;;
        --window-title=*)
            window_title="${1#--window-title=}"
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
        -R | --recipient)
            recipient="$2"
            shift 2
            ;;
        --recipient=*)
            recipient="${1#--recipient=}"
            shift
            ;;
        -t | --type)
            alert_type="$2"
            shift 2
            ;;
        --type=*)
            alert_type="${1#--type=}"
            shift
            ;;
        -c | --command)
            command="$2"
            shift 2
            ;;
        --command=*)
            command="${1#--command=}"
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

if [[ -z "$mode" ]]; then
    if [[ -n "${SSH_TTY:-}${SSH_CLIENT:-}${SSH_CONNECTION:-}" ]]; then
        mode="remote"
    elif command -v osascript &>/dev/null; then
        mode="local"
    else
        echo "Warning: no sink exists for notifications" >&2
        exit 0
    fi
fi

if [[ -n "$command" ]]; then
    set +e
    bash -c "$command"
    exit_code=$?
    set -e
    title="${title:-$command}"
    if [[ $exit_code -eq 0 ]]; then
        alert_type="success"
        message="${message:-Command succeeded}"
    else
        alert_type="error"
        message="${message:-Command failed (exit $exit_code)}"
    fi
    force=1
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

get_alert_style() {
    local icon colour
    case "${1:-}" in
        success)
            icon="SF=checkmark.circle.fill"
            colour="#A3BE8C"
            ;;
        warning)
            icon="SF=exclamationmark.triangle.fill"
            colour="#EBCB8B"
            ;;
        error)
            icon="SF=xmark.octagon.fill"
            colour="#B48EAD"
            ;;
        request)
            icon="SF=questionmark.circle.fill"
            colour="#88C0D0"
            ;;
        *)
            icon=""
            colour="#81A1C1"
            ;;
    esac
    echo "$icon" "$colour"
}

send_alert() {
    local alert_title="$1" msg="$2"
    afplay /System/Library/Sounds/Glass.aiff &
    if [[ -n "$msg" ]]; then
        if command -v dialog &>/dev/null; then
            local icon colour
            read -r icon colour < <(get_alert_style "$alert_type")
            local args=(
                --title "$alert_title"
                --message "$msg"
                --small
                --ontop
                --messagefont "size=11"
            )
            [[ -n "$icon" ]] && args+=(--icon "$icon,colour=$colour")
            dialog "${args[@]}" &
        else
            osascript -e "display alert \"$alert_title\" message \"$msg\"" >/dev/null &
        fi
    fi
}

build_message() {
    local body=""
    [[ -n "$title" ]] && body="## $title"
    if [[ -n "$message" ]]; then
        [[ -n "$body" ]] && body="$body"$'\n\n'"$message" || body="$message"
    fi
    echo "$body"
}

host="${HOSTNAME:-$(hostname -s)}"
win_title="${window_title:-$host}"

if [[ "$mode" == "local" ]]; then
    if ! command -v osascript &>/dev/null; then
        echo "Error: --local requires macOS (osascript not found)" >&2
        exit 1
    fi

    log_debug "--- ding invoked ---"
    msg=$(build_message)

    if [[ $force -eq 0 ]] && ghostty_is_focused && tmux_window_is_active; then
        log_debug "Caller focused, bell only"
        send_bell
    else
        log_debug "Sound + alert"
        send_alert "$win_title" "$msg"
    fi
else
    msg=$(build_message)
    [[ -z "$msg" ]] && msg="ding"

    ntfy_args=(--topic ding --title "$win_title" --recipient "$recipient")
    [[ -n "$alert_type" ]] && ntfy_args+=(--alert-type "$alert_type")
    ntfy-me "${ntfy_args[@]}" "$msg"
fi
