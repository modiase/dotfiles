if _is_hg
    hg rebase $argv
else
    git rebase $argv
end
