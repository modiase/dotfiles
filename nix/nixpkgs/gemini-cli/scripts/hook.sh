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
    local agents_md
    agents_md=$(generate-agents-md --agent gemini)
    jq -n --arg ctx "$agents_md" '{
      "systemMessage": "Agent configuration loaded",
      "hookSpecificOutput": { "additionalContext": $ctx }
    }'
}

notify() {
    local title="$1" message="$2" alert_type="${3:-}"
    local args=(--focus-pane -i "$title" -m "$message")
    if [[ -n "$alert_type" ]]; then args+=(-t "$alert_type"); fi
    clog info "dispatch: $title"
    ding "${args[@]}" >/dev/null
}

on_before_agent() {
    local ctx="MANDATORY: Before taking any action this turn, reason through the following in your thinking tokens (NOT in your visible response):
1. CURRENT STATE: What is the current state of the task? What has been completed so far?
2. THIS TURN: What specific action are you about to take and why?
3. REMAINING INSTRUCTIONS: List the explicit instructions from the user, GEMINI.md, and AGENTS.md that apply to your current task. Quote them directly.

After reasoning through the above, proceed with ONLY the action described in (2).

CONSTRAINTS (mandatory for this turn):
- Execute ONLY what was explicitly requested. No follow-up actions.
- If ambiguous, ask for clarification rather than assuming.
- Scope changes to exactly what was asked. Do not expand into broader refactors.
- Do not commit, deploy, push, or run destructive operations unless explicitly instructed.
- Comply with all project instructions (GEMINI.md, AGENTS.md) without exception.
- When the task is complete, stop. Do not suggest or begin additional work."

    if [[ "$PWD" == */google/src/cloud/* ]]; then
        ctx+=$'\n\n'"REMINDER: You are in google3. For codebase search and exploration, use codesearch MCP tools — not find, fd, rg, or grep (they cannot index google3). These tools are fine only for specific known file paths."
    fi

    jq -n --arg ctx "$ctx" '{
      "hookSpecificOutput": { "additionalContext": $ctx }
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
