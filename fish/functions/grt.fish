if _is_hg
    cd (hg root)
else
    git rev-parse --show-toplevel &>/dev/null; and cd (git rev-parse --show-toplevel); or echo "Not in a git repo"
end
