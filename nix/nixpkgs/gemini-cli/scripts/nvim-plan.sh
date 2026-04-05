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

session_dir="$(dirname "$(dirname "$plan_file")")"
PIDFILE="$session_dir/plan-responder.pid"
FIFO_PATH_FILE="$session_dir/plan-fifo"
if [[ -f "$PIDFILE" ]]; then
    kill "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
fi
rm -f "$FIFO_PATH_FILE"

FIFO="/tmp/nvim-plan-$(uuidgen | tr '[:upper:]' '[:lower:]').fifo"
mkfifo "$FIFO"
echo "$FIFO" >"$FIFO_PATH_FILE"

setsid agents-plan-responder --fifo "$FIFO" --pane "$TMUX_PANE" --provider gemini \
    --wrapper-id "$WRAPPER_ID" </dev/null &>/dev/null &
echo $! >"$PIDFILE"

clog info "opening file=$plan_file socket=$NVIM_SOCKET fifo=$FIFO"

nvr_exit=0
nvr_stderr=$(nvr --servername "$NVIM_SOCKET" \
    -c "lua require('utils.gemini-plan').open('$plan_file', '$FIFO')" 2>&1) || nvr_exit=$?
clog debug "nvr open+setup exit=$nvr_exit stderr=$nvr_stderr"

if [[ -n "${TARGET_PANE:-}" ]]; then
    clog info "refocusing pane=${TARGET_PANE}"
    tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true
fi
exit 0
