set -l watch 0
set -l rest
for arg in $argv
    switch $arg
        case -w --watch
            set watch 1
        case '*'
            set -a rest $arg
    end
end

if _is_hg
    if test $watch -eq 1
        viddy -t -w hg --color always xl $rest
    else
        hg xl $rest
    end
else if test $watch -eq 1
    viddy -t -w git -c color.ui=always log --oneline $rest
else
    git log --oneline $rest
end
