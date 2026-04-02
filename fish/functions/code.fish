argparse h/help 'n/name=' 'a/agent=' no-rename no-debug -- $argv
or return

if set -q _flag_help
    echo "Usage: code [OPTIONS] [DIR]"
    echo ""
    echo "Create development layout with yazi, neovim, and terminal"
    echo ""
    echo "Options:"
    echo "  -n, --name=NAME   Override tmux window name (default: lowercased dirname)"
    echo "  -a, --agent=NAME  Add agent column (gemini, claude, open, opencode)"
    echo "  --no-rename       Don't rename tmux window"
    echo "  --no-debug        Don't add devlogs pane"
    echo ""
    echo "Layout: yazi | nvim / terminal | agent (optional) / devlogs (default)"
    return 0
end

set -l dir (test (count $argv) -gt 0; and realpath $argv[1]; or echo $PWD)
test -d "$dir"; or begin
    echo "Error: not a directory: $dir" >&2
    return 1
end

test -z "$TMUX"; and echo "Error: code requires tmux" >&2; and return 1

set -l win (tmux display-message -p '#{window_id}')

set -l pane_count (tmux list-panes -t $win | wc -l | string trim)
if test "$pane_count" -ne 1
    set -l cmd code
    set -q _flag_name; and set -a cmd -n $_flag_name
    set -q _flag_agent; and set -a cmd -a $_flag_agent
    set -q _flag_no_rename; and set -a cmd --no-rename
    set -q _flag_no_debug; and set -a cmd --no-debug
    test -n "$argv[1]"; and set -a cmd $argv[1]
    set -l fish_cmd (string join ' ' -- (string escape -- $cmd))
    set -l new_win (tmux new-window -P -F '#{window_id}' -c "$dir")
    tmux send-keys -t $new_win "$fish_cmd" Enter
    return 0
end

cd "$dir"

if not set -q _flag_no_rename
    set -l win_name (string lower (basename $PWD))
    set -q _flag_name; and set win_name $_flag_name
    tmux rename-window -t $win $win_name
end

set -l agent_cmd
if set -q _flag_agent
    switch $_flag_agent
        case gemini
            set agent_cmd gemini
        case claude
            set agent_cmd claude
        case open opencode
            set agent_cmd opencode
        case '*'
            echo "Error: unknown agent '$_flag_agent' (use: gemini, claude, open)" >&2
            return 1
    end
end

set -l has_agent (test -n "$agent_cmd"; and echo 1; or echo 0)
set -l has_debug (not set -q _flag_no_debug; and echo 1; or echo 0)

set -l need (math 3 + $has_agent + $has_debug)
for i in (seq 2 $need)
    tmux split-window -t $win
end

# Pane order: yazi(0), nvim(1), [agent(2)], terminal, [devlogs]
if test $has_agent -eq 1 -a $has_debug -eq 1
    tmux select-layout -t $win '2351,384x92,0,0{40x92,0,0,75,343x92,41,0[343x81,41,0{222x81,41,0,76,120x81,264,0,78},343x10,41,82{222x10,41,82,77,120x10,264,82,79}]}'
else if test $has_agent -eq 1
    tmux select-layout -t $win '2b65,384x92,0,0{40x92,0,0,71,343x92,41,0[343x81,41,0{222x81,41,0,72,120x81,264,0,74},343x10,41,82,73]}'
else if test $has_debug -eq 1
    tmux select-layout -t $win '4cfa,384x92,0,0{40x92,0,0,80,343x92,41,0[343x81,41,0,81,343x10,41,82{222x10,41,82,82,120x10,264,82,83}]}'
else
    tmux select-layout -t $win '1d6e,384x92,0,0{40x92,0,0,67,343x92,41,0[343x81,41,0,68,343x10,41,82,69]}'
end

tmux send-keys -t $win.0 yazi Enter
tmux send-keys -t $win.1 nvim Enter

if test $has_agent -eq 1
    tmux send-keys -t $win.2 "$agent_cmd" Enter
end

if test $has_debug -eq 1
    set -l debug_pane (math $need - 1)
    tmux send-keys -t $win.$debug_pane devlogs Enter
end
