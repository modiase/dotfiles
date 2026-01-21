if _is_hg
    hg add $argv
else
    git add $argv
end
