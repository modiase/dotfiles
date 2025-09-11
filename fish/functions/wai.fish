set_color yellow
echo -n "Cwd:    "
set_color cyan
echo (pwd)
set_color normal

if git_is_repo
    set_color green
    echo -n "Repo:   "
    set_color cyan
    echo -n (git rev-parse --show-toplevel)
    echo -n "/.git"
    echo ""
    set_color normal

    set_color blue
    echo -n "Branch: "
    set_color normal
    set branch (git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if test -n "$branch"
        set_color cyan
        if test "$branch" = HEAD
            echo -n "Not on a branch"
        else
            echo -n "$branch"
        end
        set_color normal
        echo ""
    end
end
