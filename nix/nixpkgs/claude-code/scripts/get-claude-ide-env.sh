# shellcheck shell=bash

eval "$(tmux-nvim-select 2>/dev/null)" || exit 1

nvim_pid=$(nvr --servername "$NVIM_SOCKET" --remote-expr 'getpid()' 2>/dev/null) || true
if [[ -z "$nvim_pid" ]]; then
    clog info "no nvim"
    exit 1
fi
clog debug "nvim_pid=$nvim_pid"

config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
lock_dir="$config_dir/ide"
if [[ ! -d "$lock_dir" ]]; then
    clog info "no lock dir"
    exit 1
fi

clog debug "scanning lock_dir=$lock_dir"
for lock_file in "$lock_dir"/*.lock; do
    if [[ ! -f "$lock_file" ]]; then continue; fi
    lock_pid=$(jq -r '.pid // empty' "$lock_file" 2>/dev/null) || true
    if [[ "$lock_pid" == "$nvim_pid" ]]; then
        port=$(basename "$lock_file" .lock)
        clog info "matched pid=$nvim_pid port=$port"
        echo "CLAUDE_CODE_SSE_PORT=$port"
        echo "ENABLE_IDE_INTEGRATION=true"
        exit 0
    fi
done

clog info "no match pid=$nvim_pid"
exit 1
