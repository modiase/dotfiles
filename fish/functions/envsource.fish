function envsource --description "Supports setting the environment for a fish shell using .env file 'export KEY=VALUE' syntax"
    argparse --name=envsource h/help v/verbose -- $argv
    if set -q _flag_h; or not set -q argv[1]
        echo "usage: envsource <file>" >&2
        return 1
    end

    for line in (cat $argv | grep -v '^#' | grep -v '^\s*$')
        set item (string split -m 1 '=' $line)
        set -gx $item[1] $item[2]
        if set -q _flag_v
            echo "export $item[1]=$item[2]"
        end
    end
end
