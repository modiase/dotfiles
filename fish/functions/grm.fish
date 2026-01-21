if _is_hg
    hg remove $argv
else
    git rm $argv
end
