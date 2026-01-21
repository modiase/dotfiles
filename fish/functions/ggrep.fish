if _is_hg
    hg grep $argv
else
    git grep $argv
end
