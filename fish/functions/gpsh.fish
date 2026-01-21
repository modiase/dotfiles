if _is_hg
    hg upload $argv
else
    git push $argv
end
