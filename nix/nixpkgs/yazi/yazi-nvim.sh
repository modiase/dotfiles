# shellcheck shell=bash
@DEVLOGS_SOURCE@
cmd="$1"
shift

SELECT_EDIT_WIN=':let _f=0 | for w in range(1,winnr("$")) | if getbufvar(winbufnr(w),"&buftype")!=#"terminal" | exe w."wincmd w" | let _f=1 | break | endif | endfor | if !_f | aboveleft vnew | endif<CR>'

get_nvim_socket() {
    eval "$(@TMUX_NVIM_SELECT@ 2>/dev/null)" || return 1
    NVIM_LISTEN_ADDRESS="$NVIM_SOCKET"
    export NVIM_LISTEN_ADDRESS TARGET_PANE
}

case "$cmd" in
    open)
        get_nvim_socket || exec nvim "$@"
        if [ -d "$1" ]; then
            clog debug "open (cd): $1"
            @NVR@ --remote-send "<C-\\><C-n>:cd $1<CR>"
        else
            clog debug "open (edit): $1"
            @NVR@ --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent edit $1<CR>"
        fi
        tmux select-pane -t "$TARGET_PANE"
        ;;
    split)
        get_nvim_socket || exec nvim "$@"
        clog debug "split: $1"
        @NVR@ --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent sp $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    vsplit)
        get_nvim_socket || exec nvim "$@"
        clog debug "vsplit: $1"
        @NVR@ --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent vs $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    cd)
        path="$1"
        [ -z "$path" ] && echo "Error: no path provided" >&2 && exit 1
        [ ! -e "$path" ] && echo "Error: path not found: $path" >&2 && exit 1
        [ -f "$path" ] && path="$(dirname "$path")"
        [ ! -d "$path" ] && echo "Error: not a directory: $path" >&2 && exit 1
        get_nvim_socket || exit 0
        clog debug "cd: $path"
        @NVR@ --remote-send "<C-\\><C-n>:cd $path<CR>"
        ;;
    *)
        echo "Usage: yazi-nvim {open|cd|split|vsplit} [args...]" >&2
        exit 1
        ;;
esac
