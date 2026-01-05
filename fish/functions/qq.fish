set -l model_choice
if test (count $argv) -gt 0
    if test $argv[1] = gemini -o $argv[1] = claude -o $argv[1] = gpt-5
        set model_choice $argv[1]
        set argv $argv[2..-1]
    else if test $argv[1] != ""
        echo "Error: Invalid model '$argv[1]'. Must be 'claude', 'gemini', or 'gpt-5'." >&2
        return 1
    end
end

if test -z "$model_choice"
    set model_choice (echo -e "claude\ngemini\ngpt-5" | fzf --prompt="Select model: ")
    if test -z "$model_choice"
        echo "No model selected." >&2
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
else if test $model_choice = gpt-5
    set modelname gpt-5
    set api_key_env OPENAI_API_KEY
    set keychain_service OPENAI_API_KEY
    set pass_key openai-api-key
else
    set modelname claude-sonnet-4-20250514
    set api_key_env ANTHROPIC_API_KEY
    set keychain_service ANTHROPIC_API_KEY
    set pass_key anthropic-api-key
end

set -l api_key (secrets get $api_key_env --pass-path secrets/$pass_key)
if test $status -ne 0
    return 1
end

set -x $api_key_env "$api_key"
gptcli --model $modelname $argv
