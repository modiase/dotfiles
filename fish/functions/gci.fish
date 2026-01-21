if _is_hg
    hg commit $argv
else
    git commit $argv
end
