# shellcheck shell=bash
eval "$(tmux-nvim-select 2>/dev/null)" || exit 1

if [[ -z "$NVIM_SOCKET" || ! -e "$NVIM_SOCKET" ]]; then
    exit 1
fi

get_free_port() {
    local port
    while true; do
        port=$((RANDOM % 16384 + 49152))
        if ! lsof -Pi :$port -sTCP:LISTEN >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
    done
}

port=$(get_free_port)
target_window=$(tmux display-message -p -t "$TARGET_PANE" '#{window_id}' 2>/dev/null) || target_window=""

all_pids="$$"
current_pid=$$
for _ in {1..5}; do
    parent_pid=$(ps -o ppid= -p "$current_pid" | tr -d ' ')
    if [[ -n "$parent_pid" && "$parent_pid" -gt 1 ]]; then
        all_pids="$all_pids $parent_pid"
        current_pid=$parent_pid
    else
        break
    fi
done

echo "export NVIM_LISTEN_ADDRESS='$NVIM_SOCKET'"
echo "export GEMINI_CLI_IDE_SERVER_PORT='$port'"
echo "export TARGET_PANE='$TARGET_PANE'"
echo "export TARGET_WINDOW='$target_window'"
echo "export IDE_PIDS='$all_pids'"
echo "export ENABLE_IDE_INTEGRATION=true"
exit 0
