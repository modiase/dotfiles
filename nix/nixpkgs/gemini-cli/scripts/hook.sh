#!/usr/bin/env bash
set -eu

usage() {
    cat <<EOF
Usage: gemini-hook <event>

Notification dispatcher for Gemini CLI hooks.

Events:
  init                Session initialized
  before-agent        Before each agent turn
  before-plan-write   Before writing a plan file
  after-plan          After plan approval (exit_plan_mode)
  stop                Agent stopped
  permission          Permission requested

Options:
  -h, --help          Show this help
EOF
    exit 0
}

on_init() {
    clog debug "init: generating agents-md"
    local agents_md
    agents_md=$(generate-agents-md --agent gemini)
    clog debug "init: agents-md length=${#agents_md}"
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
    clog debug "before-agent: pwd=$PWD"
    local ctx="MANDATORY: Before taking any action this turn, reason through the following in your thinking tokens (NOT in your visible response):
1. FOCUS: Recite the active TODO + position — completed actions, remaining actions (in order). New user request? Evaluate via interrupt policy.
2. CURRENT STATE: State of the active action — what context do I have, what do I need?
3. THIS TURN: The single action to take now, and why.
4. REMAINING INSTRUCTIONS: Quote applicable instructions from user, GEMINI.md, AGENTS.md.
5. CONTINUITY: After this action, what's next in the TODO? If TODO done, which TODO is next?

After reasoning, proceed with ONLY the action in (3).

INTERRUPT POLICY (new user request mid-TODO):
- Quick+urgent: do immediately, resume TODO next turn
- Substantial+urgent: switch now, create TODO for interrupted work's remaining actions, acknowledge
- Substantial+deferrable: keep active TODO, create new TODO for request, acknowledge
- Quick+deferrable: note in thinking, handle after current TODO
- Default: bare requests = urgent

CONSTRAINTS (mandatory for this turn):
- Execute ONLY what was explicitly requested. No follow-up actions.
- If ambiguous, ask for clarification rather than assuming.
- Scope changes to exactly what was asked. Do not expand into broader refactors.
- Do not commit, deploy, push, or run destructive operations unless explicitly instructed.
- Comply with all project instructions (GEMINI.md, AGENTS.md) without exception.
- When the task is complete, stop. Do not suggest or begin additional work.
- If the user's request contains ambiguity or could be interpreted multiple ways, ask for clarification. State the ambiguity explicitly.
- If the user makes a claim that conflicts with evidence you have seen (code, logs, tool output), state the conflicting evidence before proceeding.
- Proactively validate assumptions that are easy to check — run a command with --help, query an available MCP resource, or fetch a web resource rather than guessing."

    if [[ "$PWD" == */google/src/cloud/* ]]; then
        ctx+=$'\n\n'"REMINDER: You are in google3. For codebase search and exploration, use codesearch MCP tools — not find, fd, rg, or grep (they cannot index google3). These tools are fine only for specific known file paths."
        clog debug "before-agent: google3 detected, added codesearch reminder"
    fi

    jq -n --arg ctx "$ctx" '{
      "hookSpecificOutput": { "additionalContext": $ctx }
    }'
}

on_before_plan_write() {
    local input
    input=$(cat)
    local file_path
    file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
    clog debug "before-plan-write: file_path=$file_path"

    if [[ "$file_path" != */.gemini/*/plans/*.md ]]; then
        clog debug "before-plan-write: not a plan file, skipping"
        exit 0
    fi

    clog debug "before-plan-write: injecting planning context"
    jq -n '{
      "hookSpecificOutput": { "additionalContext": "Before writing this plan, ensure you have:\n1. Stated what is OUT OF SCOPE — what you will NOT change and why\n2. Resolved any ambiguities in the user\u0027s request — if uncertain, ask before writing\n3. Made each item concrete — specific files, functions, and the nature of each change" }
    }'
}

on_after_plan() {
    clog debug "after-plan: injecting implementation context"
    jq -n '{
      "hookSpecificOutput": { "additionalContext": "The plan has been approved. Implementation is now mandatory:\n1. Create TODOs for each item agreed in the plan\n2. Execute each TODO until all are completed\n3. During implementation, greater tolerance of ambiguity is encouraged — conform to what was agreed in the plan and explain decisions after the fact\n4. Only ask the user for clarification on IMPORTANT decisions — those with data integrity implications, security implications, or that break existing conventions" }
    }'
}

on_stop() {
    clog debug "stop: agent stopped"
    notify '#{t_window_name}' 'Agent stopped'
}

on_permission() {
    clog debug "permission: request received"
    notify 'Gemini CLI' 'Permission needed' request
}

case "${1:-}" in
    -h | --help) usage ;;
    init) on_init ;;
    before-agent) on_before_agent ;;
    before-plan-write) on_before_plan_write ;;
    after-plan) on_after_plan ;;
    stop) on_stop ;;
    permission) on_permission ;;
    *)
        echo "Unknown event: ${1:-}" >&2
        exit 1
        ;;
esac
