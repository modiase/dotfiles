#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: claude-hook <event>

Notification dispatcher for Claude Code hooks.

Events:
  init                Session initialized
  stop                Agent stopped
  permission          Permission requested

Options:
  -h, --help          Show this help
EOF
    exit 0
}

on_init() {
    clog debug "init: session started pwd=$PWD"
    echo '{}'
}

notify() {
    local title="$1" message="$2" alert_type="${3:-}"
    local args=(--focus-pane -i "$title" -m "$message")
    if [[ -n "$alert_type" ]]; then args+=(-t "$alert_type"); fi
    clog info "dispatch: $title"
    ding "${args[@]}" >/dev/null
}

focus_pane() {
    osascript -e 'tell app "Ghostty" to activate' >/dev/null 2>/dev/null || true
    if [[ -n "${TMUX_PANE:-}" ]]; then
        local win_idx
        win_idx=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
        local pane_idx
        pane_idx=$(tmux display-message -t "$TMUX_PANE" -p '#{pane_index}' 2>/dev/null) || true
        if [[ -n "${win_idx:-}" && -n "${pane_idx:-}" ]]; then
            tmux select-window -t ":$win_idx" 2>/dev/null || true
            tmux select-pane -t ":$win_idx.$pane_idx" 2>/dev/null || true
        fi
    fi
}

on_stop() {
    clog debug "stop: agent stopped"
    notify '#{t_window_name}' 'Agent stopped'
}

on_permission() {
    local input
    input=$(cat)
    clog debug "permission: request received input=$input"

    local tool_name msg detail
    tool_name=$(printf '%s\n' "$input" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
    detail=""

    case "$tool_name" in
        Bash)
            detail=$(printf '%s\n' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || detail=""
            ;;
        Read | Write | Edit)
            detail=$(printf '%s\n' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || detail=""
            ;;
    esac

    if [[ -n "$tool_name" ]]; then
        msg="$tool_name"
        if [[ -n "$detail" ]]; then
            if [[ ${#detail} -gt 100 ]]; then
                detail="${detail:0:97}..."
            fi
            msg="$tool_name: $detail"
        fi
    else
        msg="Permission needed"
    fi

    local result actions='Allow,Show'
    if [[ "$tool_name" == "ExitPlanMode" ]]; then actions='Show'; fi
    result=$(ding -i 'Claude Code' -m "$msg" --actions "$actions")
    case "$result" in
        Allow)
            clog info "permission: allowed via dialog"
            jq -n '{
                "hookSpecificOutput": {
                    "hookEventName": "PermissionRequest",
                    "decision": { "behavior": "allow" }
                }
            }'
            ;;
        Show)
            focus_pane
            ;;
    esac
}

event="${1:-}"
shift || true
_wrapper_id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wrapper-id)
            _wrapper_id="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done

case "$event" in
    -h | --help) usage ;;
    init) on_init ;;
    stop) on_stop ;;
    permission) on_permission ;;
    *)
        echo "Unknown event: $event" >&2
        exit 1
        ;;
esac
