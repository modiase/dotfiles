set -l default_branch (get_default_branch)
if test $status -ne 0
    echo "Failed to determine default branch" >&2
    return 1
end
git rebase $default_branch $argv
