set EXIT_FAILURE 1
function debug
    if [ $DEBUG -gt 0 ]
        echo $argv
    end
end

function exit_on_failed_command --on-event command-failed
    exit $EXIT_FAILURE
end

function fail -a reason
    echo $reason >&2
    exit $EXIT_FAILURE
end

function mkbackup -a node
    if not test -d "$node"; and not test -f "$node"
        return
    else if not test -d "$node.bk"; and not test -f "$node.bk"
        set -f new_node "$node.bk"
    else
        set -f count 0
        set -f new_node "$node.bk.$count"
        while test -d "$new_node"; or test -f "$new_node"
            set -f count (math $count + 1)
            set -f new_node "$node.bk.$count"
        end
    end
    if test -L $node
        set -f resolved (realpath $node)
        debug "$node -> $new_node -> $resolved"
        rm $node
        ln -s $resolved $new_node
    else
        debug "$node -> $new_node"
        mv $node $new_node
    end

end

function softreplace -a source dest
    if test -L "$dest"; and test (realpath $source) = (realpath $dest)
        return
    else if test -f "$dest"; or test -d "$dest"
        if not test (cat "$source"| $SHASUM) = (cat "$dest"| $SHASUM)
            mkbackup "$dest"
            ln -s "$source" "$dest"
        end
    else
        mkdir -p (dirname "$dest")
        ln -s "$source" "$dest"
    end
end

set -q DEBUG; or set -gx DEBUG 0
if [ $DEBUG -eq 2 ]
    set fish_trace 1
end

if command -v shasum &>/dev/null
    set SHASUM shasum
else if command -v sha1sum &>/dev/null
    set SHASUM sha1sum
else
    echo "Unable to find suitable hash function"
    exit $EXIT_FAILURE
end
