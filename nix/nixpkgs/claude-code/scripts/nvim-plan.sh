# shellcheck shell=bash
cat >/dev/null

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
plans_dir="$config_dir/plans"

if [[ ! -d "$plans_dir" ]]; then exit 0; fi

# shellcheck disable=SC2012 # plan filenames are UUIDs, safe for ls
PLAN_FILE=$(ls -t "$plans_dir"/*.md 2>/dev/null | head -1)
if [[ -z "$PLAN_FILE" ]]; then exit 0; fi

eval "$(tmux-nvim-select 2>/dev/null)" || exit 0
if [[ -z "${NVIM_SOCKET:-}" ]]; then exit 0; fi

nvr --servername "$NVIM_SOCKET" \
    --remote-tab-silent "$PLAN_FILE" \
    -c "lua require('utils.claude-plan').setup_buffer('$config_dir', '$TMUX_PANE')" 2>/dev/null || true

if [[ -n "${TARGET_PANE:-}" ]]; then tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true; fi
exit 0
