if _is_hg
    hg shelve $argv
else
    git stash $argv
end
