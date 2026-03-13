# shellcheck shell=bash
cat >/dev/null

eval "$(tmux-nvim-select 2>/dev/null)" || exit 0
if [[ -z "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim socket"
    exit 0
fi

clog info "closing socket=$NVIM_SOCKET"
nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.claude-plan').close()" 2>/dev/null || true
exit 0
