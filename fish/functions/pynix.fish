function pynix -d "Create a python environment with the specified packages using nix."
    argparse --name=pynix h/help 'v/version=' -- $argv
    if set -q _flag_h
        echo Help
        return 0
    end

    set -l py_version 313
    if set -q _flag_v
        set py_version (echo $_flag_v | awk -F '.' '{ print $1$2 }')
    end

    set -l nix_command "nix-shell -p ruff -p python"$py_version
    for package in $argv
        set nix_command $nix_command -p python$py_version"Packages."$package
    end
    echo "$nix_command"
    env fish_prompt_prefix=pynix $nix_command --command fish
end
