#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: ding [OPTIONS]

Notification tool that adapts to context (tmux, focus state, local/remote).

Options:
  -c, --command CMD       Run command, alert success/error based on exit code
  -f, --force-alert       Always play sound/alert (skip focus detection)
  -i, --title TEXT        Notification title
  -m, --message TEXT      Notification message
  -R, --recipient HOST    Target recipient for remote (default: * for all)
  -t, --type TYPE         Alert type: success, warning, error, request
  --focus-pane            Capture tmux pane; click notification to focus
  --local                 Force local mode (macOS)
  --no-bell               Disable terminal bell
  --no-sound              Disable alert sound
  --remote                Force remote mode (ntfy-me)
  --debug                 Log debug info to /tmp/ding-debug.log
  -h, --help              Show this help

Tmux placeholders (expanded in --title, --message):
  #{t_window_index}  Current tmux window index
  #{t_window_name}   Current tmux window name
  #{t_pane_index}    Current tmux pane index

Behaviour:
  Local mode:
    - Always plays a sound and sends bell to terminal
    - Shows notification only if Ghostty is not focused
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

debug=0
focus_pane=""
force=0
no_bell=0
no_sound=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage ;;
        --debug)
            debug=1
            exec 3>>/tmp/ding-debug.log
            BASH_XTRACEFD=3
            set -x
            shift
            ;;
        -f | --force-alert)
            force=1
            shift
            ;;
        --focus-pane)
            if [[ -n "${TMUX_PANE:-}" ]]; then
                window_idx=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
                pane_idx=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_index}' 2>/dev/null) || true
                [[ -n "$window_idx" && -n "$pane_idx" ]] && focus_pane="$window_idx:$pane_idx" || true
            fi
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
        --no-bell)
            no_bell=1
            shift
            ;;
        --no-sound)
            no_sound=1
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
        -w | --window-title | --window-title=*)
            shift
            [[ "${1:-}" != -* ]] && shift || true
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

expand_tmux_vars() {
    local text="$1"
    [[ -z "${TMUX_PANE:-}" ]] && {
        echo "$text"
        return
    }
    [[ "$text" != *'#{t_'* ]] && {
        echo "$text"
        return
    }

    local win_index win_name pane_index
    win_index=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || win_index=""
    win_name=$(tmux display-message -t "$TMUX_PANE" -p '#{window_name}' 2>/dev/null) || win_name=""
    pane_index=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_index}' 2>/dev/null) || pane_index=""

    text="${text//\#\{t_window_index\}/$win_index}"
    text="${text//\#\{t_window_name\}/$win_name}"
    text="${text//\#\{t_pane_index\}/$pane_index}"
    echo "$text"
}

title=$(expand_tmux_vars "$title")
message=$(expand_tmux_vars "$message")

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
    if [[ $exit_code -eq 0 ]]; then
        alert_type="success"
        title="${title:-Command}"
        message="${message:-$command succeeded}"
    else
        alert_type="error"
        title="${title:-Command}"
        message="${message:-$command failed (exit $exit_code)}"
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
    [[ $no_bell -eq 1 ]] && return 0
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
    send_bell

    local notifier=""
    if command -v terminal-notifier &>/dev/null; then
        notifier="terminal-notifier"
    elif [[ -x /opt/homebrew/bin/terminal-notifier ]]; then
        notifier="/opt/homebrew/bin/terminal-notifier"
    elif [[ -x /usr/local/bin/terminal-notifier ]]; then
        notifier="/usr/local/bin/terminal-notifier"
    fi

    if [[ -z "$notifier" ]]; then
        [[ -n "$msg" ]] && osascript -e "display alert \"$alert_title\" message \"$msg\"" >/dev/null &
        return 0
    fi

    local args=(-title "$alert_title")
    [[ -n "$msg" ]] && args+=(-message "$msg")
    [[ $no_sound -eq 0 ]] && args+=(-sound default)

    if [[ -n "$focus_pane" ]]; then
        local win="${focus_pane%:*}"
        args+=(-execute "osascript -e 'tell app \"Ghostty\" to activate' && tmux select-window -t ':$win' && tmux select-pane -t ':$focus_pane'")
    fi

    "$notifier" "${args[@]}" &
}

if [[ "$mode" == "local" ]]; then
    if ! command -v osascript &>/dev/null; then
        echo "Error: --local requires macOS (osascript not found)" >&2
        exit 1
    fi

    log_debug "--- ding invoked ---"

    if [[ $force -eq 0 ]] && ghostty_is_focused && tmux_window_is_active; then
        log_debug "Caller focused, bell only"
        send_bell
    else
        log_debug "Sound + alert"
        send_alert "${title:-ding}" "$message"
    fi
else
    ntfy_args=(--topic ding --recipient "$recipient")
    [[ -n "$title" ]] && ntfy_args+=(--title "$title")
    [[ -n "$alert_type" ]] && ntfy_args+=(--alert-type "$alert_type")
    ntfy-me "${ntfy_args[@]}" "${message:-ding}"
fi
