if _is_hg
    hg update $argv
else
    git checkout $argv
end
