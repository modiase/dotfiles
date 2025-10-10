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
set token_file "$HOME/.ping-me.json"

set access_token ""
if test -f "$token_file" -a -z "$_flag_revalidate"
    if set -q _flag_verbose
        echo "Found existing token file: $token_file"
    end

    set token_data (cat "$token_file" 2>/dev/null)
    if test -n "$token_data"
        set access_token (echo "$token_data" | jq -r '.access_token // empty' 2>/dev/null)
        set expires_at (echo "$token_data" | jq -r '.expires_at // empty' 2>/dev/null)

        if test -n "$expires_at"
            set current_time (date +%s)
            if set -q _flag_verbose
                echo "Token expires at: $expires_at ($(date -d @$expires_at 2>/dev/null || date -r $expires_at 2>/dev/null || echo "unknown"))"
                echo "Current time: $current_time ($(date))"
            end

            if test "$current_time" -ge "$expires_at"
                if set -q _flag_verbose
                    echo "Token has expired, will fetch new one"
                end
                set access_token ""
            else
                if set -q _flag_verbose
                    set time_remaining (math $expires_at - $current_time)
                    echo "Token is valid for $time_remaining more seconds"
                end
            end
        else
            if set -q _flag_verbose
                echo "Token file missing expiration time, will fetch new one"
            end
            set access_token ""
        end
    else
        if set -q _flag_verbose
            echo "Token file is empty, will fetch new one"
        end
    end
else
    if set -q _flag_verbose
        if test -n "$_flag_revalidate"
            echo "Revalidation requested, will fetch new token"
        else
            echo "No token file found at: $token_file"
        end
    end
end

if test -z "$access_token" -o -n "$_flag_revalidate"
    if set -q _flag_verbose
        echo "Fetching new OAuth2 token..."
        echo "Token endpoint: https://auth.modiase.dev/api/oidc/token"
    end

    set client_secret (gcloud secrets versions access latest --secret=authelia-client-credentials-secret --project=modiase-infra 2>/dev/null)
    if test -z "$client_secret"
        echo "Failed to fetch client secret"
        return 1
    end

    if set -q _flag_verbose
        echo "Making OAuth2 token request..."
        echo "Client ID: ntfy-client"
        echo "Grant type: client_credentials"
        echo "Scope: authelia.bearer.authz"
        echo "Audience: https://ntfy.modiase.dev"
    end

    set token_response (curl -s -w "%{http_code}|" -X POST "https://auth.modiase.dev/api/oidc/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -u "ntfy-client:$client_secret" \
        -d "grant_type=client_credentials&scope=authelia.bearer.authz&audience=https://ntfy.modiase.dev")

    set token_http_code (string split -m 1 "|" "$token_response")[2]
    set token_body (string split -m 1 "|" "$token_response")[1]

    if set -q _flag_verbose
        echo "OAuth2 Response HTTP Code: $token_http_code"
        echo "OAuth2 Response Body: $token_body"
    end

    if test "$token_http_code" != 200
        echo "Failed to get OAuth2 token: HTTP $token_http_code"
        if set -q _flag_verbose
            echo "Response body: $token_body"
        end
        return 1
    end

    set access_token (echo "$token_body" | jq -r '.access_token // empty' 2>/dev/null)
    set expires_in (echo "$token_body" | jq -r '.expires_in // empty' 2>/dev/null)

    if test -z "$access_token" -o "$access_token" = null
        echo "Failed to get access token from response"
        if set -q _flag_verbose
            echo "Token response: $token_body"
        end
        return 1
    end

    if set -q _flag_verbose
        echo "Access token obtained successfully"
        echo "Token expires in: $expires_in seconds"
    end

    set expires_at (math (date +%s) + "$expires_in" - 60)

    echo "{\"access_token\":\"$access_token\",\"expires_at\":$expires_at}" >"$token_file"
    chmod 600 "$token_file"
end

set -l attempt 1
set -l wait_time 1

if set -q _flag_verbose
    echo "Starting message send attempts (max: $max_tries)"
    echo "Message: $message"
    echo "Target URL: https://ntfy.modiase.dev/general"
    echo "Max wait between retries: $max_wait seconds"
end

while test $attempt -le $max_tries
    if set -q _flag_verbose
        echo "--- Attempt $attempt ---"
        echo "Making POST request to ntfy..."
        echo "Headers: Authorization: Bearer [REDACTED], Content-Type: text/plain"
        echo "Body length: "(string length "$message")" characters"
    end

    set response (curl -s -L -w "|%{http_code}|%{time_total}|%{size_download}|" \
        -H "Authorization: Bearer $access_token" \
        -H "Content-Type: text/plain" \
        -d "$message" \
        "https://ntfy.modiase.dev/general")

    set response_parts (string split "|" "$response")
    set response_body "$response_parts[1]"
    set http_code "$response_parts[2]"
    set time_total "$response_parts[3]"
    set size_download "$response_parts[4]"

    if set -q _flag_verbose
        echo "HTTP Status Code: $http_code"
        echo "Response time: $time_total seconds"
        echo "Response size: $size_download bytes"
        echo "Response body: $response_body"
    end

    if test "$http_code" = 200
        if set -q _flag_verbose
            echo "✓ Message sent successfully!"
            echo "Total time: $time_total seconds"
        end
        return 0
    end

    if test $attempt -eq $max_tries
        echo "Failed to send message after $max_tries attempts (HTTP $http_code)"
        if set -q _flag_verbose
            echo "Final response body: $response_body"
            echo "Total attempts made: $attempt"
        end
        return 1
    end

    set wait_time (math "min($wait_time * 2, $max_wait)")

    if set -q _flag_verbose
        echo "✗ Attempt $attempt failed (HTTP $http_code)"
        echo "Response body: $response_body"
        echo "Waiting $wait_time seconds before retry..."
        echo ""
    else
        echo "Attempt $attempt failed (HTTP $http_code), retrying in $wait_time seconds..."
    end

    sleep $wait_time
    set attempt (math $attempt + 1)
end
