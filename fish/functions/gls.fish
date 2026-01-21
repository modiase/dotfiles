if _is_hg
    hg files $argv
else
    git ls-files $argv
end
