if _is_hg
    hg merge $argv
else
    git merge $argv
end
