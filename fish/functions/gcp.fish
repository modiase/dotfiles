if _is_hg
    hg graft $argv
else
    git cherry-pick $argv
end
