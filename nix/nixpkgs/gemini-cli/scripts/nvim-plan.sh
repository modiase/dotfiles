# shellcheck shell=bash
stdin=$(cat)
clog debug "raw stdin: $stdin"

plan_file=$(echo "$stdin" | jq -r '.tool_input.file_path // empty')
clog debug "extracted file_path=$plan_file"

if [[ -z "$plan_file" ]]; then
    clog debug "no file_path in payload, exiting"
    exit 0
fi
if [[ "$plan_file" != */.gemini/*/plans/*.md ]]; then
    clog debug "not a plan file, exiting"
    exit 0
fi

clog info "plan file detected: $plan_file"

eval "$(tmux-nvim-select 2>/dev/null)" || {
    clog info "tmux-nvim-select failed"
    exit 0
}
if [[ -z "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim socket"
    exit 0
fi

clog info "opening file=$plan_file socket=$NVIM_SOCKET pane=${TARGET_PANE:-} tmux_pane=${TMUX_PANE:-}"

nvr_exit=0
nvr_stderr=$(nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.gemini-plan').close()" 2>&1) || nvr_exit=$?
clog debug "nvr close exit=$nvr_exit stderr=$nvr_stderr"

nvr_exit=0
nvr_stderr=$(nvr --servername "$NVIM_SOCKET" \
    --remote-tab-silent "$plan_file" \
    -c "lua require('utils.gemini-plan').setup_buffer('${TMUX_PANE:-}')" 2>&1) || nvr_exit=$?
clog debug "nvr open+setup exit=$nvr_exit stderr=$nvr_stderr"

if [[ -n "${TARGET_PANE:-}" ]]; then
    clog info "refocusing pane=${TARGET_PANE}"
    tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true
fi
exit 0
