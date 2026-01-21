if _is_hg
    hg diff $argv | delta
else
    git diff $argv
end
