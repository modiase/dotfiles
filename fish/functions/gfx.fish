if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
    echo "Error: Not in a git repository" >&2
    return 1
end

if not git diff --cached --quiet
else
    echo "Did you mean to add some changes using git add?" >&2
    return 1
end

set -l default_branch (get_default_branch)
if test $status -ne 0
    echo "Failed to determine default branch" >&2
    return 1
end

set -l merge_base (git merge-base HEAD $default_branch)
if test $status -ne 0
    echo "Failed to find merge base with $default_branch" >&2
    return 1
end

set -l selected_commit (
    git log --oneline --no-show-signature --color=always $merge_base..HEAD | \
    fzf --ansi \
        --prompt="Select commit to fixup> " \
        --preview='git show --color=always --stat --patch {1}' \
        --preview-window=right:60%
)

if test $status -ne 0 -o -z "$selected_commit"
    echo "No commit selected"
    return 1
end

set -l commit_hash (string split --field 1 " " $selected_commit)

git commit --fixup=$commit_hash
if test $status -ne 0
    echo "Failed to create fixup commit" >&2
    return 1
end

git rebase --autosquash $merge_base
