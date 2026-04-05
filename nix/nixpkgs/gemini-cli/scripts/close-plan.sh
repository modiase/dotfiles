# shellcheck shell=bash
_wrapper_id=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --wrapper-id)
            _wrapper_id="$2"
            shift 2
            ;;
        *) shift ;;
    esac
done
stdin=$(cat)

plan_file=$(echo "$stdin" | jq -r '.tool_input.file_path // empty')
if [[ -z "$plan_file" || "$plan_file" != */.gemini/*/plans/*.md ]]; then
    exit 0
fi

session_dir="$(dirname "$(dirname "$plan_file")")"
FIFO_PATH_FILE="$session_dir/plan-fifo"
PIDFILE="$session_dir/plan-responder.pid"

if [[ ! -f "$FIFO_PATH_FILE" ]]; then
    exit 0
fi

FIFO=$(cat "$FIFO_PATH_FILE")

if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
fi

eval "$(tmux-nvim-select 2>/dev/null)" || true
if [[ -n "${NVIM_SOCKET:-}" ]]; then
    nvr --servername "$NVIM_SOCKET" \
        -c "lua require('utils.gemini-plan').close_by_fifo('$FIFO')" 2>/dev/null || true
fi

rm -f "$FIFO" "$FIFO_PATH_FILE"
exit 0
