if _is_hg
    hg backout $argv
else
    git revert $argv
end
