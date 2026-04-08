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
    clog debug "dispatch: $title"
    attn "${args[@]}" >/dev/null
}

focus_pane() {
    attn focus
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
    if [[ "$tool_name" == "ExitPlanMode" || "$tool_name" == "AskUserQuestion" ]]; then actions='Show'; fi
    result=$(attn -i 'Claude Code' -m "$msg" --actions "$actions")
    case "$result" in
        Allow)
            clog info "permission: allowed via dialog — $msg"
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
