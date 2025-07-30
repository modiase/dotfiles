set -l model_choice claude
if test (count $argv) -gt 0
    if test $argv[1] = gemini -o $argv[1] = claude
        set model_choice $argv[1]
        set argv $argv[2..-1]
    else if test $argv[1] != ""
        echo "Error: Invalid model '$argv[1]'. Must be 'claude' or 'gemini'." >&2
        return 1
    end
end

set -l modelname
set -l api_key_env
set -l keychain_service
set -l pass_key

if test $model_choice = gemini
    set modelname gemini-2.5-flash
    set api_key_env GEMINI_API_KEY
    set keychain_service GEMINI_API_KEY
    set pass_key gemini-api-key
else
    set modelname claude-sonnet-4-20250514
    set api_key_env ANTHROPIC_API_KEY
    set keychain_service ANTHROPIC_API_KEY
    set pass_key anthropic-api-key
end

if set -q $api_key_env
    gptcli --model $modelname $argv
    return
end

set -l api_key
if test (uname) = Darwin
    set api_key (security find-generic-password -w -s "$keychain_service" 2>/dev/null)
    if test $status -ne 0
        echo "Error: $model_choice API key not found in macOS Keychain." >&2
        echo "Please add it by running:" >&2
        echo "security add-generic-password -a \"\$USER\" -s \"$keychain_service\" -w \"YOUR_API_KEY\"" >&2
        return 1
    end
else
    if not test -d "$HOME/.password-store"
        echo "Error: pass password store is not initialized." >&2
        echo "Please initialize it by running: pass init <gpg-id>" >&2
        return 1
    end
    set api_key (pass show $pass_key 2>/dev/null)
    if test $status -ne 0
        echo "Error: $model_choice API key '$pass_key' not found in pass." >&2
        echo "Please add it by running:" >&2
        echo "pass insert $pass_key" >&2
        return 1
    end
end

set -x $api_key_env "$api_key"
gptcli --model $modelname $argv
