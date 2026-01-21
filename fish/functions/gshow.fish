if _is_hg
    hg log -p -r $argv
else
    git show $argv
end
