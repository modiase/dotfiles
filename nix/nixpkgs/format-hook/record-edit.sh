# shellcheck shell=bash
input=$(cat)

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
    clog debug "no file_path in tool_input, skipping"
    exit 0
fi

session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
if [[ -z "$session_id" ]]; then
    clog debug "no session_id, skipping"
    exit 0
fi

clog debug "recording edit: $file_path"
printf '%s\n' "$file_path" >>"/tmp/claude-edits-${session_id}"
