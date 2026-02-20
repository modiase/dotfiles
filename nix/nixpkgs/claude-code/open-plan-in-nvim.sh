# shellcheck shell=bash
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[[ "$FILE_PATH" != "$config_dir"/plans/*.md ]] && exit 0

nvr -c "lua require('utils.claude-plan').open('$FILE_PATH', '$config_dir')" 2>/dev/null || true
exit 0
