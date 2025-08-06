if test (count $argv) -lt 2
    echo "Usage: with <directory> <command> [args...]" >&2
    return 1
end

set -l target_dir $argv[1]
set -l cmd $argv[2..-1]

if not test -d $target_dir
    echo "Error: '$target_dir' is not a directory" >&2
    return 1
end

pushd $target_dir >/dev/null
eval $cmd
set -l exit_code $status
popd >/dev/null

return $exit_code
