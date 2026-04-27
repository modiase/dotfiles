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
        viddy -t -w hg --color always status $rest
    else
        hg status $rest
    end
else if test $watch -eq 1
    viddy -t -w git -c status.color=always status --short $rest
else
    git status $rest
end
