# shellcheck shell=bash
cat >/dev/null

clog debug "close-plan invoked"

eval "$(tmux-nvim-select 2>/dev/null)" || {
    clog debug "tmux-nvim-select failed"
    exit 0
}
if [[ -z "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim socket"
    exit 0
fi

clog info "closing socket=$NVIM_SOCKET"
nvr_exit=0
nvr_stderr=$(nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.gemini-plan').close()" 2>&1) || nvr_exit=$?
clog debug "nvr close exit=$nvr_exit stderr=$nvr_stderr"
exit 0
