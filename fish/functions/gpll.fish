if _is_hg
    hg sync $argv
else
    git pull $argv
end
