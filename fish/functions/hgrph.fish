if _is_hg
    viddy -n 2 -t -w hg xl $argv
else
    viddy -n 2 -t -w -x git log --graph --topo-order --color=always \
        '--format=%C(bold yellow)%h%C(reset) %s%C(auto)%d %C(dim)(%cr)%C(reset)' \
        HEAD --all $argv
end
