if _is_hg
    hg sync $argv
    return
end
set -l remote (if set -q argv[1]; echo $argv[1]; else; echo origin; end)
if set -q argv[1]
    set --erase argv[1]
end
set -l default_branch (get_default_branch)
if test $status -ne 0
    echo "Failed to determine default branch" >&2
    return 1
end
set -l current_branch (git rev-parse --abbrev-ref HEAD)
if test $current_branch = $default_branch
    git pull $remote
    return 0
end
gfch $remote $default_branch:$default_branch &>/dev/null; and echo "Updated $default_branch from $remote"; or echo "Warning: could not fetch updates from $remote. Is it defined?"
git rebase $default_branch $argv
