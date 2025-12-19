argparse h/help 'rev=' 'n/num=' no-auto-accept-changes -- $argv
or return

if test -n "$_flag_help"
    echo "Usage: gfx [OPTIONS]"
    echo ""
    echo "Git fixup - interactively select a commit to fixup and autosquash rebase"
    echo ""
    echo "Options:"
    echo "  -h, --help                  Show this help message"
    echo "  --rev=REVISION              Base revision for finding commits (default: main)"
    echo "  -n, --num=NUMBER            Number of commits back from HEAD to use as base"
    echo "  --no-auto-accept-changes    Don't automatically amend hook-modified files during rebase"
    echo ""
    echo "Examples:"
    echo "  gfx                         # Fixup commits since main"
    echo "  gfx --rev=develop           # Fixup commits since develop branch"
    echo "  gfx -n 5                    # Fixup commits in last 5 commits"
    echo "  gfx --no-auto-accept-changes # Manual review of hook changes"
    return 0
end

if test -n "$_flag_rev" -a -n "$_flag_num"
    echo "Error: Cannot use both --rev and -n/--num" >&2
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

if test -z "$_flag_rev" -a -z "$_flag_num"
    set _flag_rev main
end

set -l merge_base
if test -n "$_flag_num"
    set merge_base HEAD~$_flag_num
else
    set merge_base (git merge-base HEAD $_flag_rev)
    if test $status -ne 0
        echo "Failed to find merge base with $_flag_rev" >&2
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

if test -z "$_flag_no_auto_accept_changes"
    # Hooks may modify files during rebase; auto-amend changes to prevent rebase halt
    git rebase --autosquash $merge_base --exec 'git diff --quiet || (git add -u && git commit --amend --no-edit --no-verify)'
else
    git rebase --autosquash $merge_base
end
