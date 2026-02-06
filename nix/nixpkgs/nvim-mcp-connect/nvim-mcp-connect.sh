#!/usr/bin/env bash
set -euo pipefail

get_nvim_socket() {
    [ -z "${TMUX:-}" ] && return 1
    local pane_id cmd
    while read -r pane_id cmd; do
        [[ "$cmd" =~ [Nn]vim ]] || continue
        local socket
        socket=$(tmux show-environment "NVIM_$pane_id" 2>/dev/null | cut -d= -f2)
        [ -S "$socket" ] && echo "$socket" && return 0
    done < <(tmux list-panes -F '#{pane_id} #{pane_current_command}')
    return 1
}

if socket=$(get_nvim_socket); then
    exec nvim-mcp --connect "$socket" "$@"
fi
exec nvim-mcp --connect auto "$@"
