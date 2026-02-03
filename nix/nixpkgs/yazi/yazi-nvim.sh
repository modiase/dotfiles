#!/usr/bin/env bash

cmd="$1"
shift

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
            nvr --remote-send "<Esc>:cd $1<CR>"
        else
            nvr --remote-send "<Esc>:silent tabedit $1<CR>"
        fi
        tmux select-pane -t "$TARGET_PANE"
        ;;
    split)
        get_nvim_socket || exec nvim "$@"
        nvr --remote-send "<Esc>:silent sp $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    vsplit)
        get_nvim_socket || exec nvim "$@"
        nvr --remote-send "<Esc>:silent vs $1<CR>"
        tmux select-pane -t "$TARGET_PANE"
        ;;
    cd)
        path="$1"
        [ -z "$path" ] && echo "Error: no path provided" >&2 && exit 1
        [ ! -e "$path" ] && echo "Error: path not found: $path" >&2 && exit 1
        [ -f "$path" ] && path="$(dirname "$path")"
        [ ! -d "$path" ] && echo "Error: not a directory: $path" >&2 && exit 1
        get_nvim_socket || exit 0
        nvr --remote-send "<Esc>:cd $path<CR>"
        ;;
    *)
        echo "Usage: yazi-nvim {open|cd|split|vsplit} [args...]" >&2
        exit 1
        ;;
esac
