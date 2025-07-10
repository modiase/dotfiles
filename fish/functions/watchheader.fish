function watchheader
    set -l file $argv[1]
    watch -n1 -x fish -c "cat (head -1 $file | psub) (tail -5 $file | psub)"
end
