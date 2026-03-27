#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: ding [OPTIONS]

Terminal notification tool. Adapts to context (macOS/Linux, SSH, tmux, focus state).

Options:
  -c, --command CMD       Run command, alert success/error based on exit code
  -f, --force-alert       Always play sound/alert (skip focus detection)
  -i, --title TEXT        Notification title
  -m, --message TEXT      Notification message
  -t, --type TYPE         Accepted for compatibility (unused locally)
  --actions "A,B"         Show dialog with buttons; print clicked label to stdout
  --focus-pane            Capture tmux pane; click notification to focus
  --no-bell               Disable terminal bell
  --no-sound              Disable alert sound
  --debug                 Enable bash trace logging
  -h, --help              Show this help

Tmux placeholders (expanded in --title, --message):
  #{t_window_index}  Current tmux window index
  #{t_window_name}   Current tmux window name
  #{t_pane_index}    Current tmux pane index

Behaviour:
  - SSH/Linux: sends OSC 9 notification + bell
  - macOS local: terminal-notifier with click-to-focus (suppressed when focused)
  - In tmux: bell triggers window flag via monitor-bell
EOF
    exit 0
}

command=""
message=""
title=""
actions=""

focus_pane=""
force=0
no_bell=0
no_sound=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h | --help) usage ;;
        --debug)
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
        -t | --type)
            shift 2
            ;;
        --type=*)
            shift
            ;;
        --actions)
            actions="$2"
            shift 2
            ;;
        --actions=*)
            actions="${1#--actions=}"
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

if [[ -n "$command" ]]; then
    set +e
    bash -c "$command"
    exit_code=$?
    set -e
    if [[ $exit_code -eq 0 ]]; then
        title="${title:-Command}"
        message="${message:-$command succeeded}"
    else
        title="${title:-Command}"
        message="${message:-$command failed (exit $exit_code)}"
    fi
    force=1
fi

ghostty_is_focused() {
    local frontmost
    frontmost=$(osascript -e 'tell application "System Events" to name of (first process whose frontmost is true)')
    clog debug "frontmost app: $frontmost"
    [[ "${frontmost,,}" == "ghostty" ]]
}

tmux_window_is_active() {
    [[ -z "${TMUX_PANE:-}" ]] && return 0
    local pane_window active_window
    pane_window=$(tmux display-message -t "$TMUX_PANE" -p '#{window_id}' 2>/dev/null) || return 1
    active_window=$(tmux display-message -p '#{window_id}' 2>/dev/null) || return 1
    clog debug "tmux window: pane=$pane_window active=$active_window"
    [[ "$pane_window" == "$active_window" ]]
}

ghostty_tab_is_active() {
    [[ -z "${TMUX_PANE:-}" ]] && return 0
    local raw
    raw=$(tmux show-environment GHOSTTY_TAB_ID 2>/dev/null) || true
    if [[ "$raw" != *=* ]]; then
        clog debug "no GHOSTTY_TAB_ID in tmux env"
        return 0
    fi
    local stored_tab_id="${raw#*=}"
    local current_tab_id
    current_tab_id=$(osascript -e '
        tell application "Ghostty"
            try
                return id of selected tab of front window
            end try
        end tell
    ' 2>/dev/null) || true
    if [[ -z "$current_tab_id" ]]; then
        clog debug "applescript unavailable, assuming tab active"
        return 0
    fi
    clog debug "tab: stored=$stored_tab_id current=$current_tab_id"
    [[ "$stored_tab_id" == "$current_tab_id" ]]
}

send_bell() {
    if [[ $no_bell -eq 1 ]]; then return 0; fi
    if [[ -n "${TMUX_PANE:-}" ]]; then
        local tty_path
        tty_path=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null) || true
        [[ -n "$tty_path" ]] && printf '\a' >"$tty_path" 2>/dev/null || true
    else
        printf '\a'
    fi
}

send_osc9() {
    local msg="$1"
    if [[ -n "${TMUX_PANE:-}" ]]; then
        local tty_path
        tty_path=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_tty}' 2>/dev/null) || true
        if [[ -n "$tty_path" ]]; then
            # shellcheck disable=SC1003
            printf '\ePtmux;\e\e]9;%s\a\e\\' "$msg" >"$tty_path" 2>/dev/null || true
        fi
    else
        printf '\e]9;%s\a' "$msg"
    fi
}

escape_applescript() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

send_action_dialog() {
    local alert_title="$1" msg="$2" action_csv="$3"
    send_bell

    local escaped_title escaped_msg
    escaped_title=$(escape_applescript "$alert_title")
    escaped_msg=$(escape_applescript "$msg")

    local button_list
    button_list="\"${action_csv//,/\", \"}\""

    local script
    printf -v script 'display dialog "%s" with title "%s" buttons {%s} giving up after 60' \
        "$escaped_msg" "$escaped_title" "$button_list"

    local result
    result=$(timeout 65 osascript -e "$script" 2>/dev/null) || true

    if [[ "$result" == *"gave up:true"* ]]; then
        return 0
    fi

    local clicked
    clicked="${result#*button returned:}"
    clicked="${clicked%%,*}"
    if [[ -n "$clicked" ]]; then
        echo "$clicked"
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
        if [[ -n "$msg" ]]; then
            osascript -e "display alert \"$alert_title\" message \"$msg\"" >/dev/null &
        fi
        return 0
    fi

    local args=(-title "$alert_title")
    if [[ -n "$msg" ]]; then args+=(-message "$msg"); fi
    if [[ $no_sound -eq 0 ]]; then args+=(-sound default); fi

    if [[ -n "$focus_pane" ]]; then
        local win="${focus_pane%:*}"
        args+=(-execute "osascript -e 'tell app \"Ghostty\" to activate' && tmux select-window -t ':$win' && tmux select-pane -t ':$focus_pane'")
    fi

    "$notifier" "${args[@]}" &
}

is_ssh=0
if [[ -n "${SSH_TTY:-}${SSH_CLIENT:-}${SSH_CONNECTION:-}" ]]; then is_ssh=1; fi

has_osascript=0
if command -v osascript &>/dev/null; then has_osascript=1; fi

if [[ $is_ssh -eq 1 ]] || [[ $has_osascript -eq 0 ]]; then
    osc_msg="${title:-ding}"
    if [[ -n "$message" ]]; then osc_msg="$osc_msg: $message"; fi
    clog info "osc9 — title='${title:-ding}' message='$message'"
    send_bell
    send_osc9 "$osc_msg"
elif [[ $force -eq 0 ]] && ghostty_is_focused && ghostty_tab_is_active && tmux_window_is_active; then
    clog debug "suppressed — focused, tab active, window active"
    send_bell
elif [[ -n "$actions" ]]; then
    clog info "action dialog — title='${title:-ding}' message='$message' actions='$actions'"
    send_action_dialog "${title:-ding}" "$message" "$actions"
else
    clog info "alert — title='${title:-ding}' message='$message'"
    send_alert "${title:-ding}" "$message"
fi
