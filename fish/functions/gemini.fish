set -l api_key (secrets get GEMINI_API_KEY --pass-path secrets/gemini-api-key)
if test $status -ne 0
    return 1
end

GEMINI_API_KEY="$api_key" command gemini $argv
