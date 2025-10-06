argparse v/verbose r/revalidate 'max-tries=' 'max-wait=' -- $argv
or return

if test (count $argv) -eq 0
    echo "Usage: ping-me [-v|--verbose] [-r|--revalidate] [--max-tries=N] [--max-wait=S] <message>"
    return 1
end

set -l max_tries $_flag_max_tries
if test -z "$max_tries"
    set max_tries 3
end

set -l max_wait $_flag_max_wait
if test -z "$max_wait"
    set max_wait 300
end

set message (string join " " $argv)
set token_dir "$HOME/.ping-me"
set token_file "$token_dir/token.json"

if not test -d "$token_dir"
    mkdir -p "$token_dir"
end

set access_token ""
if test -f "$token_file" -a -z "$_flag_revalidate"
    set token_data (cat "$token_file" 2>/dev/null)
    if test -n "$token_data"
        set access_token (echo "$token_data" | jq -r '.access_token // empty' 2>/dev/null)
        set expires_at (echo "$token_data" | jq -r '.expires_at // empty' 2>/dev/null)

        if test -n "$expires_at"
            set current_time (date +%s)
            if test "$current_time" -ge "$expires_at"
                set access_token ""
            end
        else
            set access_token ""
        end
    end
end

if test -z "$access_token" -o -n "$_flag_revalidate"
    if set -q _flag_verbose
        echo "Fetching new OAuth2 token..."
    end

    set client_secret (gcloud secrets versions access latest --secret=authelia-client-credentials-secret --project=modiase-infra 2>/dev/null)
    if test -z "$client_secret"
        echo "Failed to fetch client secret"
        return 1
    end

    set token_response (curl -s -X POST "https://auth.modiase.dev/api/oidc/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -u "ntfy-client:$client_secret" \
        -d "grant_type=client_credentials&scope=authelia.bearer.authz&audience=https://ntfy.modiase.dev")

    set access_token (echo "$token_response" | jq -r '.access_token // empty' 2>/dev/null)
    set expires_in (echo "$token_response" | jq -r '.expires_in // empty' 2>/dev/null)

    if test -z "$access_token" -o "$access_token" = null
        echo "Failed to get access token"
        return 1
    end

    set expires_at (math (date +%s) + "$expires_in" - 60)

    echo "{\"access_token\":\"$access_token\",\"expires_at\":$expires_at}" >"$token_file"
    chmod 600 "$token_file"
end

set -l attempt 1
set -l wait_time 1

while test $attempt -le $max_tries
    set response (curl -s -L -w "%{http_code}" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: text/plain" \
        -d "$message" \
        "https://ntfy.modiase.dev/general")

    set http_code (string sub -s -3 "$response")

    if test "$http_code" = 200
        if set -q _flag_verbose
            echo "Message sent successfully!"
        end
        return 0
    end

    if test $attempt -eq $max_tries
        echo "Failed to send message after $max_tries attempts (HTTP $http_code)"
        return 1
    end

    set wait_time (math "min($wait_time * 2, $max_wait)")

    if set -q _flag_verbose
        echo "Attempt $attempt failed (HTTP $http_code), retrying in $wait_time seconds..."
    end

    sleep $wait_time
    set attempt (math $attempt + 1)
end
