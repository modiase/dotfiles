if _is_hg
    hg amend $argv
else
    git commit --amend --no-edit $argv
end
