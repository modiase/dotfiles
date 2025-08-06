set -l default_branch (get_default_branch)
if test $status -ne 0
    echo "Failed to determine default branch" >&2
    return 1
end
git fetch origin $default_branch:$default_branch; and git rebase $default_branch
