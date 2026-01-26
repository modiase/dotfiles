set -l activate_script "$HOME/dotfiles/bin/activate"

test -x "$activate_script"; or begin
    echo "Error: $activate_script not found or not executable" >&2
    return 1
end

pushd "$HOME/dotfiles" >/dev/null
set -l ret 0
if contains -- --local $argv
    set -l args (string match -v -- '--local' $argv)
    $activate_script $args; or set ret $status
else
    $activate_script deploy $argv; or set ret $status
end
popd >/dev/null
return $ret
