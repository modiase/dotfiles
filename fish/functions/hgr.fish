if _is_hg
    viddy -n 2 -t -w hg --color always xl $argv
else
    viddy -n 2 -t -w -x bash -c 'git log --graph --topo-order --color=always \
        --format="%C(bold yellow)%h%C(reset) %s%C(auto)%d %C(dim)(%cr)%C(reset)" \
        HEAD "$@" | sed -E \
        -e "s/([0-9]+) seconds? ago/\1s/g" \
        -e "s/([0-9]+) minutes? ago/\1m/g" \
        -e "s/([0-9]+) hours? ago/\1h/g" \
        -e "s/([0-9]+) days? ago/\1d/g" \
        -e "s/([0-9]+) weeks? ago/\1w/g" \
        -e "s/([0-9]+) months? ago/\1mo/g" \
        -e "s/([0-9]+) years? ago/\1y/g"' -- $argv
end
