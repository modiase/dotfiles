#!/usr/bin/env bash

cmd="$1"
shift

# Vimscript to find first non-terminal window, or create left-split if none exist
SELECT_EDIT_WIN=':let _f=0 | for w in range(1,winnr("$")) | if getbufvar(winbufnr(w),"&buftype")!=#"terminal" | exe w."wincmd w" | let _f=1 | break | endif | endfor | if !_f | aboveleft vnew | endif<CR>'

get_nvim_socket() {
    [ -z "$TMUX" ] && return 1
    TARGET_PANE=$(tmux list-panes -F '#{pane_id} #{pane_current_command}' | grep -i nvim | head -n 1 | cut -d' ' -f1)
    [ -z "$TARGET_PANE" ] && return 1
    NVIM_LISTEN_ADDRESS=$(tmux show-environment "NVIM_$TARGET_PANE" 2>/dev/null | cut -d= -f2)
    [ -z "$NVIM_LISTEN_ADDRESS" ] || [ ! -e "$NVIM_LISTEN_ADDRESS" ] && return 1
    export NVIM_LISTEN_ADDRESS TARGET_PANE
}

case "$cmd" in
    open)
        get_nvim_socket || exec nvim "$@"
        if [ -d "$1" ]; then
            nvr --remote-send "<C-\\><C-n>:cd $1<CR>"
        else
            nvr --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent edit $1<CR>"
        fi
        tmux select-pane -t "$TARGET_PANE"
        ;;
    split)
        get_nvim_socket || exec nvim "$@"
        nvr --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent sp $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    vsplit)
        get_nvim_socket || exec nvim "$@"
        nvr --remote-send "<C-\\><C-n>${SELECT_EDIT_WIN}:silent vs $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    cd)
        path="$1"
        [ -z "$path" ] && echo "Error: no path provided" >&2 && exit 1
        [ ! -e "$path" ] && echo "Error: path not found: $path" >&2 && exit 1
        [ -f "$path" ] && path="$(dirname "$path")"
        [ ! -d "$path" ] && echo "Error: not a directory: $path" >&2 && exit 1
        get_nvim_socket || exit 0
        nvr --remote-send "<C-\\><C-n>:cd $path<CR>"
        ;;
    *)
        echo "Usage: yazi-nvim {open|cd|split|vsplit} [args...]" >&2
        exit 1
        ;;
esac
