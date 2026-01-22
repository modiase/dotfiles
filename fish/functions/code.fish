argparse h/help 'a/agent=' no-rename -- $argv
or return

if set -q _flag_help
    echo "Usage: code [OPTIONS]"
    echo ""
    echo "Create development layout with yazi, neovim, and terminal"
    echo ""
    echo "Options:"
    echo "  -a, --agent=NAME  Add agent column (gemini or claude)"
    echo "  --no-rename       Don't rename tmux window"
    echo ""
    echo "Layout: yazi (left) | nvim (top-right) / terminal (bottom-right)"
    return 0
end

test -z "$TMUX"; and echo "Error: code requires tmux" >&2; and return 1

set -l pane_count (tmux list-panes | wc -l | string trim)
test "$pane_count" -ne 1; and echo "Error: code requires exactly 1 pane (current: $pane_count)" >&2; and return 1

not set -q _flag_no_rename; and tmux rename-window (string lower (basename $PWD))

set -l agent_cmd
if set -q _flag_agent
    switch $_flag_agent
        case gemini
            set agent_cmd gemini
        case claude
            set agent_cmd claude
        case '*'
            echo "Error: unknown agent '$_flag_agent' (use: gemini, claude)" >&2
            return 1
    end
end

# Layout: yazi (20%) | nvim (top) / terminal (bottom) | agent (25%, optional)
# Split: left 20% for yazi, right 80% for rest
tmux split-window -h -p 80

# Now in right pane (nvim area). Split for terminal (bottom 33%)
tmux split-window -v -p 33
tmux select-pane -U

if test -n "$agent_cmd"
    # Split nvim area: left for nvim, right 25% for agent
    tmux split-window -h -p 25
    tmux send-keys "$agent_cmd" Enter
    tmux select-pane -L
end

tmux send-keys nvim Enter

tmux select-pane -t :.0
tmux send-keys yazi Enter
