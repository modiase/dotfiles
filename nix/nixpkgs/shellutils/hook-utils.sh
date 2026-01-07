#!/usr/bin/env bash

EXIT_HOOKS=()

add_exit_hook() { EXIT_HOOKS+=("$1"); }

run_exit_hooks() {
    local i
    for ((i = ${#EXIT_HOOKS[@]} - 1; i >= 0; i--)); do
        eval "${EXIT_HOOKS[i]}" || true
    done
}

trap run_exit_hooks EXIT
