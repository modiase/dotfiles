if test (count $argv) -ne 1
    echo "Error: gtrck requires exactly one argument" >&2
    echo "Usage: gtrck <remote-name/branch-name> or gtrck <branch-name>" >&2
    return 1
end

set -l parts (string split "/" $argv[1])
set -l parts_count (count $parts)

if test $parts_count -eq 1
    set remote origin
    set branch $parts[1]
else if test $parts_count -eq 2
    set remote $parts[1]
    set branch $parts[2]
else
    echo "Error: Invalid argument format. Expected 'remote/branch' or 'branch'" >&2
    echo "Usage: gtrck <remote-name/branch-name> or gtrck <branch-name>" >&2
    return 1
end

set -l current_branch (git branch --show-current)
git branch --set-upstream-to="$remote/$branch" $current_branch
