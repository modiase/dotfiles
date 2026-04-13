# shellcheck shell=bash
input=$(cat)

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
    clog debug "no file_path in tool_input, skipping"
    exit 0
fi

format_file "$file_path"
