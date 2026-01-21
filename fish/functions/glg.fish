if _is_hg
    hg xl $argv
else
    git log --oneline $argv
end
