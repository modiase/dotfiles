#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: gemini-hook <event>

Notification dispatcher for Gemini CLI hooks.

Events:
  init                Session initialized
  before-agent        Before each agent turn
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

_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} gemini-hook${win}: $*"
}

notify() {
    local title="$1" message="$2" alert_type="${3:-}"
    local args=(--focus-pane -i "$title" -m "$message")
    if [[ -n "$alert_type" ]]; then args+=(-t "$alert_type"); fi
    clog info "dispatch: $title"
    ding "${args[@]}" >/dev/null
}

on_before_agent() {
    if [[ "$PWD" != */google/src/cloud/* ]]; then return 0; fi
    jq -n '{
      "hookSpecificOutput": {
        "additionalContext": "REMINDER: You are in google3. For codebase search and exploration, use codesearch MCP tools — not find, fd, rg, or grep (they cannot index google3). These tools are fine only for specific known file paths."
      }
    }'
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
    before-agent) on_before_agent ;;
    stop) on_stop ;;
    permission) on_permission ;;
    *)
        echo "Unknown event: ${1:-}" >&2
        exit 1
        ;;
esac
