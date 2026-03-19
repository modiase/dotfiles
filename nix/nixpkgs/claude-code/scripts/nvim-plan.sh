# shellcheck shell=bash
cat >/dev/null

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
plans_dir="$config_dir/plans"

if [[ ! -d "$plans_dir" ]]; then
    clog info "no plans dir"
    exit 0
fi

# shellcheck disable=SC2012 # plan filenames are UUIDs, safe for ls
PLAN_FILE=$(ls -t "$plans_dir"/*.md 2>/dev/null | head -1)
if [[ -z "$PLAN_FILE" ]]; then
    clog info "no plan file"
    exit 0
fi

eval "$(tmux-nvim-select 2>/dev/null)" || {
    clog info "no nvim socket"
    exit 0
}
if [[ -z "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim socket"
    exit 0
fi

FIFO="/tmp/nvim-plan-$(uuidgen | tr '[:upper:]' '[:lower:]').fifo"
mkfifo "$FIFO"

setsid agents-plan-responder --fifo "$FIFO" --pane "$TMUX_PANE" --provider claude \
    --nvim-socket "$NVIM_SOCKET" </dev/null &>/dev/null &

clog info "opening file=$PLAN_FILE socket=$NVIM_SOCKET fifo=$FIFO"

nvr_exit=0
nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.claude-plan').open('$PLAN_FILE', '$config_dir', '$FIFO')" 2>/dev/null || nvr_exit=$?
if [[ $nvr_exit -ne 0 ]]; then clog error "nvr open failed exit=$nvr_exit"; fi

if [[ -n "${TARGET_PANE:-}" ]]; then
    clog info "refocusing pane=${TARGET_PANE}"
    tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true
fi
exit 0
