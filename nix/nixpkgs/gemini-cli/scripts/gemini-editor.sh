# shellcheck shell=bash

FILE="${1:?Usage: gemini-editor <file>}"

eval "$(tmux-nvim-select 2>/dev/null)" || true

if [[ -z "${NVIM_SOCKET:-}" || ! -e "${NVIM_SOCKET:-}" ]]; then
    clog info "no nvim, launching directly"
    exec nvim "$FILE"
fi

clog info "nvim found socket=$NVIM_SOCKET pane=${TARGET_PANE:-}"

is_plan=false
if [[ "$FILE" == */.gemini/*/plans/* ]]; then
    is_plan=true
fi

cleanup() {
    tput cnorm 2>/dev/null || true
    clear 2>/dev/null || true
}
trap cleanup EXIT

if $is_plan; then
    clog info "plan file detected, opening read-only"
    nvr --servername "$NVIM_SOCKET" \
        --remote-tab-wait "$FILE" \
        -c "lua require('utils.gemini-plan').setup_buffer()" &
else
    nvr --servername "$NVIM_SOCKET" \
        --remote-tab-wait +'setlocal bufhidden=delete' "$FILE" &
fi
nvr_pid=$!

if [[ -n "${TARGET_PANE:-}" ]]; then
    tmux select-pane -t "$TARGET_PANE" 2>/dev/null || true
fi

clear
tput civis 2>/dev/null || true

cols=$(tput cols 2>/dev/null || echo 80)
lines=$(tput lines 2>/dev/null || echo 24)
pad=$((lines * 2 / 5))

label="Editing file in nvim..."
$is_plan && label="Reviewing plan in nvim..."

printf '%*s' "$pad" '' | tr ' ' $'\n'
gum style --width="$cols" --align=center --bold --foreground 212 "$label"
echo
gum style --width="$cols" --align=center --faint "Close the buffer to return to Gemini CLI"

wait "$nvr_pid" || true
