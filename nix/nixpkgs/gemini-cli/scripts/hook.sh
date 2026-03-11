#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: gemini-hook <event>

Notification dispatcher for Gemini CLI hooks. Uses ding locally, ntfy-me over SSH.

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
    local nvim_context="CRITICAL: Neovim integration is available. You MUST call the 'connect' tool with target=auto IMMEDIATELY. This is a mandatory prerequisite. Do NOT attempt to list buffers, read files, or run diagnostics until the connection is established. This connection is required for all IDE and LSP features."
    local agents_md
    agents_md=$(generate-agents-md --agent gemini)
    local context
    context=$(printf '%s\n\n%s' "$nvim_context" "$agents_md")
    jq -n --arg ctx "$context" '{
      "systemMessage": "Agent configuration loaded",
      "hookSpecificOutput": { "additionalContext": $ctx }
    }'
}

notify() {
    local title="$1" message="$2" alert_type="${3:-}"

    if [[ -n "${SSH_TTY:-}${SSH_CLIENT:-}${SSH_CONNECTION:-}" ]]; then
        args=(--topic ding --title "$title")
        [[ -n "$alert_type" ]] && args+=(--alert-type "$alert_type")
        ntfy-me "${args[@]}" "$message" >/dev/null
    else
        args=(--focus-pane -i "$title" -m "$message")
        [[ -n "$alert_type" ]] && args+=(-t "$alert_type")
        ding "${args[@]}" >/dev/null
    fi
}

on_stop() {
    notify '#{t_window_name}' 'Agent stopped'
}

on_permission() {
    notify 'Gemini CLI' 'Permission needed' request
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
