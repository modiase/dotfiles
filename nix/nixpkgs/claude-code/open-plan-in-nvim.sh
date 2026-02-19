# shellcheck shell=bash
INPUT=$(cat)

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -z "$FILE_PATH" ]] && exit 0
[[ "$FILE_PATH" != /tmp/claude-nix/plans/*.md ]] && exit 0

nvr -c "lua require('utils.claude-plan').open('$FILE_PATH')" 2>/dev/null || true

exit 0
