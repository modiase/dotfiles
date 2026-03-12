#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: claude-hook <event>

Notification dispatcher for Claude Code hooks. Uses ding locally, ntfy-me over SSH.

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
    cat <<EOF
{
  "additionalContext": "Neovim integration is available. You MUST call mcp__nvim__connect with target=auto IMMEDIATELY before using any nvim MCP tools."
}
EOF
}

clog() {
    local level="$1"
    shift
    logger -t devlogs -p "user.$level" "claude-hook: $*"
}

notify() {
    local title="$1" message="$2" alert_type="${3:-}"

    if [[ -n "${SSH_TTY:-}${SSH_CLIENT:-}${SSH_CONNECTION:-}" ]]; then
        clog info "remote dispatch via ntfy-me: $title"
        args=(--topic ding --title "$title")
        [[ -n "$alert_type" ]] && args+=(--alert-type "$alert_type")
        ntfy-me "${args[@]}" "$message" >/dev/null
    else
        clog info "local dispatch via ding: $title"
        args=(--focus-pane -i "$title" -m "$message")
        [[ -n "$alert_type" ]] && args+=(-t "$alert_type")
        ding "${args[@]}" >/dev/null
    fi
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
