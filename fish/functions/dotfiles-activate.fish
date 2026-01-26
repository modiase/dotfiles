set -l activate_script "$HOME/Dotfiles/bin/activate"

test -x "$activate_script"; or begin
    echo "Error: $activate_script not found or not executable" >&2
    return 1
end

if contains -- --local $argv
    set -l args (string match -v -- '--local' $argv)
    $activate_script $args
else
    $activate_script deploy $argv
end
