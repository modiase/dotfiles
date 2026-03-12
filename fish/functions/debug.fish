set -l args
if set -q TMUX_PANE
    set args $argv
else
    set args --all $argv
end
devlogs $args
