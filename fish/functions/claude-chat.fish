if set -q ANTHROPIC_API_KEY
    gpt --model claude $argv
    return
end

set -l api_key
if test (uname) = "Darwin"
    set api_key (security find-generic-password -w -s "ANTHROPIC_API_KEY" 2>/dev/null)
    if test $status -ne 0
        echo "Error: Anthropic API key not found in macOS Keychain." >&2
        echo "Please add it by running:" >&2
        echo 'security add-generic-password -a "$USER" -s "ANTHROPIC_API_KEY" -w "YOUR_API_KEY"' >&2
        return 1
    end
else
    if not test -d "$HOME/.password-store"
        echo "Error: pass password store is not initialized." >&2
        echo "Please initialize it by running: pass init <gpg-id>" >&2
        return 1
    end
    set api_key (pass show anthropic-api-key 2>/dev/null)
    if test $status -ne 0
        echo "Error: Anthropic API key 'anthropic-api-key' not found in pass." >&2
        echo "Please add it by running:" >&2
        echo 'pass insert anthropic-api-key' >&2
        return 1
    end
end

ANTHROPIC_API_KEY="$api_key" gpt --model claude $argv
