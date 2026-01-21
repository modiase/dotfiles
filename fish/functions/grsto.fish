if _is_hg
    hg revert $argv
else
    git restore $argv
end
