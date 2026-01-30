set -l activate_script "$HOME/dotfiles/bin/activate"

test -x "$activate_script"; or begin
    echo "Error: $activate_script not found or not executable" >&2
    return 1
end

set -l escaped_args (string escape -- $argv)

if contains -- --local $argv
    set -l args (string match -v -- '--local' $argv)
    set escaped_args (string escape -- $args)
    fish -c "$activate_script $escaped_args"
else
    fish -c "$activate_script deploy $escaped_args"
end
