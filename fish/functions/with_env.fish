function usage
    echo "with_env <envfile> <command...>"
end

function with_env
    if test -z $argv[1]; or not test -f $argv[1]; or test -z $argv[2]
        usage
        return 1
    end
    set -l envfile (realpath "$argv[1]")
    set -l cmd "$argv[2..]"
    fish -c "envsource $envfile && $cmd"
end
