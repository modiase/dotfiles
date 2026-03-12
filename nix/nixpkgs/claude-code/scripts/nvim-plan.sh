# shellcheck shell=bash
cat >/dev/null

_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} nvim-plan${win}: $*"
}

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

clog info "opening file=$PLAN_FILE socket=$NVIM_SOCKET pane=${TARGET_PANE:-}"

nvr_exit=0
nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.claude-plan').close()" 2>/dev/null || nvr_exit=$?
if [[ $nvr_exit -ne 0 ]]; then clog error "nvr close failed exit=$nvr_exit"; fi

nvr_exit=0
nvr --servername "$NVIM_SOCKET" \
    --remote-tab-silent "$PLAN_FILE" \
    -c "lua require('utils.claude-plan').setup_buffer('$config_dir', '$TMUX_PANE')" 2>/dev/null || nvr_exit=$?
if [[ $nvr_exit -ne 0 ]]; then clog error "nvr open failed exit=$nvr_exit"; fi

if [[ -n "${TARGET_PANE:-}" ]]; then
    clog info "refocusing pane=${TARGET_PANE}"
    tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true
fi
exit 0
