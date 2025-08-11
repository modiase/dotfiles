set -l default_branch (get_default_branch)
if test $status -ne 0
    echo "Failed to determine default branch" >&2
    return 1
end
gfch origin $default_branch:$default_branch &>/dev/null; and echo "Updated $default_branch from origin"; or echo 'Warning: could not fetch updates from origin. Is it defined?'
git rebase $default_branch $argv
