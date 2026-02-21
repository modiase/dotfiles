# shellcheck shell=bash
INPUT=$(cat)

TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
[[ -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]] && exit 0

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
plans_pattern="$config_dir/plans/"

PLAN_FILE=$(tail -100 "$TRANSCRIPT_PATH" | jq -r '
  select(.message.content) |
  .message.content |
  if type == "array" then .[] else . end |
  select(.type == "tool_use" and (.name == "Write" or .name == "Edit")) |
  .input.file_path // empty
' 2>/dev/null | grep "$plans_pattern" | tail -1)

[[ -z "$PLAN_FILE" ]] && exit 0

nvr -c "lua require('utils.claude-plan').open('$PLAN_FILE', '$config_dir')" 2>/dev/null || true
exit 0
