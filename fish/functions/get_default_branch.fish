if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
    echo "Error: Not in a git repository" >&2
    return 1
end

# Try to get the default branch from remote origin
set -l remote_default (LC_ALL=C git remote show origin 2>/dev/null | sed -n '/HEAD branch/s/.*: //p')
if test -n "$remote_default"
    echo $remote_default
    return 0
end

# Fallback: check if main or master exists locally
set -l has_main (git show-ref --verify --quiet refs/heads/main; echo $status)
set -l has_master (git show-ref --verify --quiet refs/heads/master; echo $status)

if test $has_main -eq 0 -a $has_master -eq 0
    echo "Error: Both 'main' and 'master' branches exist. Cannot determine default." >&2
    return 2
else if test $has_main -eq 0
    echo main
    return 0
else if test $has_master -eq 0
    echo master
    return 0
end

# Last resort: use whatever branch we're currently on
git branch --show-current 2>/dev/null; or begin
    echo "Error: Cannot determine default branch" >&2
    return 1
end
