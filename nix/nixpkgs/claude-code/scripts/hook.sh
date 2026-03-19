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

on_stop() {
    clog debug "stop: agent stopped"
    notify '#{t_window_name}' 'Agent stopped'
}

on_permission() {
    clog debug "permission: request received"
    notify 'Claude Code' 'Permission needed' request
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
