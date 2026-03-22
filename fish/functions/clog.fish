set -l valid_levels debug info warning error
set -l level info
set -l msg

if contains -- $argv[1] $valid_levels
    set level $argv[1]
    set msg (string join " " $argv[2..])
else
    set msg (string join " " $argv)
end

set -l win ""
test -n "$TMUX_PANE"; and set win "(@"(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null)")"

set -l priority "user.$level"
test "$level" = debug; and set priority "user.info"

set -l label (string upper $level)
set -l component (test -n "$DEVLOGS_COMPONENT"; and echo $DEVLOGS_COMPONENT; or echo "fish")
set -l instance (test -n "$DEVLOGS_INSTANCE"; and echo $DEVLOGS_INSTANCE; or echo "-")

logger -t devlogs -p "$priority" "[devlogs] $label $component{$instance}$win: $msg"
