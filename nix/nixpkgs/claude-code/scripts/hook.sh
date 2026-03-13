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
    notify '#{t_window_name}' 'Agent stopped'
}

on_permission() {
    notify 'Claude Code' 'Permission needed' request
}

case "${1:-}" in
    -h | --help) usage ;;
    init) on_init ;;
    stop) on_stop ;;
    permission) on_permission ;;
    *)
        echo "Unknown event: ${1:-}" >&2
        exit 1
        ;;
esac
