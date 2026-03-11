# shellcheck shell=bash
cat >/dev/null

eval "$(tmux-nvim-select 2>/dev/null)" || exit 0
[[ -z "${NVIM_SOCKET:-}" ]] && exit 0
nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.claude-plan').close()" 2>/dev/null || true
exit 0
