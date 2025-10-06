argparse 'r/ref=' 'n/num=' -- $argv
or return

if test -n "$_flag_ref" -a -n "$_flag_num"
    echo "Error: Cannot use both -r/--ref and -n/--num" >&2
    return 1
end

if not git rev-parse --is-inside-work-tree >/dev/null 2>&1
    echo "Error: Not in a git repository" >&2
    return 1
end

if not git diff --cached --quiet
else
    echo "Did you mean to add some changes using git add?" >&2
    return 1
end

if test -z "$_flag_ref" -a -z "$_flag_num"
    set _flag_ref main
end

set -l merge_base
if test -n "$_flag_num"
    set merge_base HEAD~$_flag_num
else
    set merge_base (git merge-base HEAD $_flag_ref)
    if test $status -ne 0
        echo "Failed to find merge base with $_flag_ref" >&2
        return 1
    end
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
