set -l is_remote 0
test -n "$SSH_TTY" -o -n "$SSH_CLIENT" -o -n "$SSH_CONNECTION"; and set is_remote 1

set -l socket_opt
set -l default_session local
if test $is_remote -eq 1
    set default_session remote
else
    set socket_opt -S /tmp/tmux-local
end

set -l ghostty_tab_id ""
if test -n "$GHOSTTY_RESOURCES_DIR"
    set ghostty_tab_id (osascript -e '
        tell application "Ghostty"
            try
                return id of selected tab of front window
            end try
        end tell
    ' 2>/dev/null)
end

set -l tab_env
if test -n "$ghostty_tab_id"
    set tab_env \; set-environment GHOSTTY_TAB_ID $ghostty_tab_id
end

set -l has_custom_socket 0
set -l other_args
set -l skip_next 0

for arg in $argv
    if test $skip_next -eq 1
        set socket_opt -S $arg
        set has_custom_socket 1
        set skip_next 0
        continue
    end
    if test "$arg" = -S
        set skip_next 1
        continue
    end
    set -a other_args $arg
end

if test (count $other_args) -eq 0
    set -l sessions (command tmux $socket_opt list-sessions -F '#{session_name}' 2>/dev/null)
    set -l session_count (count $sessions)

    if test $session_count -eq 0
        command tmux $socket_opt new-session -s $default_session $tab_env
    else if test $session_count -eq 1
        command tmux $socket_opt attach -t $sessions[1] $tab_env
    else
        set -l choice (printf "%s\n" "Create new ($default_session)" $sessions | gum choose --header "Select session:")
        test -z "$choice"; and return 1
        if string match -q "Create new*" "$choice"
            command tmux $socket_opt new-session -s $default_session $tab_env
        else
            command tmux $socket_opt attach -t $choice $tab_env
        end
    end
else
    if test $has_custom_socket -eq 1
        command tmux $socket_opt $other_args
    else
        command tmux $socket_opt $argv
    end
end
