if _is_hg
    hg status $argv
else
    git status $argv
end
