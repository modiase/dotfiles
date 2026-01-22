if _is_hg
    test (count $argv) -eq 0; and set argv .
    hg upload $argv
else
    git push $argv
end
