if set -q ANTHROPIC_API_KEY
    command claude $argv
    return
end

set -l api_key
if test (uname) = Darwin
    set api_key (security find-generic-password -w -s "ANTHROPIC_API_KEY" 2>/dev/null)
    if test $status -ne 0
        set -e api_key
    end
else
    if test -d "$HOME/.password-store"
        set api_key (pass show anthropic-api-key 2>/dev/null)
        if test $status -ne 0
            set -e api_key
        end
    end
end

set -l cmd "command claude"
if set -q api_key
    set cmd "ANTHROPIC_API_KEY=\"$api_key\" $cmd"
end

eval $cmd $argv
