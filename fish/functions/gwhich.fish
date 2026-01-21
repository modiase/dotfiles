if _is_hg
    hg branch $argv
else
    git branch --show $argv
end
