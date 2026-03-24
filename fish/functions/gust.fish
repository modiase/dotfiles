set -l staged (git diff --cached --name-only)
if test -z "$staged"
    echo "Nothing to unstage"
    return 0
end

set -l selected (
    printf '%s\n' $staged | \
    fzf --multi \
        --header="Select files to unstage (enter: toggle, c: confirm)" \
        --bind='enter:toggle,c:accept' \
        --preview='git diff --cached --color=always -- {}' \
        --preview-window=right:60%
)

if test -z "$selected"
    return 0
end

git restore --staged -- $selected

echo "Unstaged:"
for file in $selected
    echo "  $file"
end
