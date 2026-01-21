if _is_hg
    hg tag $argv
else
    git tag $argv
end
