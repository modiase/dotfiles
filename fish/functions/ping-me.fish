argparse v/verbose r/revalidate 't/topic=' 'max-tries=' 'max-wait=' -- $argv
or return

if test (count $argv) -eq 0
    echo "Usage: ping-me [-v|--verbose] [-r|--revalidate] [-t|--topic=TOPIC] [--max-tries=N] [--max-wait=S] <message>"
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

set -l topic $_flag_topic
if test -z "$topic"
    set topic general
end

set message (string join " " $argv)
set auth_file "$HOME/.ping-me.json"

set password ""
test -f "$auth_file" -a -z "$_flag_revalidate"; and set password (cat "$auth_file" 2>/dev/null | jq -r '.password // empty' 2>/dev/null)
test "$password" = null; and set password ""

set -q _flag_verbose; and begin
    test -f "$auth_file"; and echo "Found existing auth file: $auth_file"; or echo "No auth file found at: $auth_file"
    test -n "$password"; and echo "Using stored password for basic auth"; or echo "Will fetch new password from Google Secrets"
    test -n "$_flag_revalidate"; and echo "Revalidation requested, will fetch new password"
end

# Fetch password if needed
if test -z "$password" -o -n "$_flag_revalidate"
    set -q _flag_verbose; and begin
        echo "Fetching ntfy password from Google Secrets..."
        echo "Secret: ntfy-basic-auth-password"
        echo "Project: modiase-infra"
    end

    set password (gcloud secrets versions access latest --secret=ntfy-basic-auth-password --project=modiase-infra 2>/dev/null)
    test -z "$password"; and begin
        echo "Failed to fetch ntfy password from Google Secrets"
        return 1
    end

    echo "{\"password\":\"$password\"}" >"$auth_file"
    chmod 600 "$auth_file"

    set -q _flag_verbose; and begin
        echo "Password retrieved successfully from Google Secrets"
        echo "Auth file saved: $auth_file"
    end
end

set -l attempt 1
set -l wait_time 1

set -q _flag_verbose; and begin
    echo "Starting message send attempts (max: $max_tries)"
    echo "Message: $message"
    echo "Topic: $topic"
    echo "Target URL: https://ntfy.modiase.dev/$topic"
    echo "Max wait between retries: $max_wait seconds"
end

while test $attempt -le $max_tries
    set -q _flag_verbose; and begin
        echo "--- Attempt $attempt ---"
        echo "Making POST request to ntfy..."
        echo "Headers: Authorization: Basic [REDACTED], Content-Type: text/plain"
        echo "Body length: "(string length "$message")" characters"
    end

    set response (curl -s -L -w "|%{http_code}|%{time_total}|%{size_download}|" \
        -u "ntfy:$password" \
        -H "Content-Type: text/plain" \
        -d "$message" \
        "https://ntfy.modiase.dev/$topic")

    set response_parts (string split "|" "$response")
    set response_body "$response_parts[1]"
    set http_code "$response_parts[2]"
    set time_total "$response_parts[3]"
    set size_download "$response_parts[4]"

    set -q _flag_verbose; and begin
        echo "HTTP Status Code: $http_code"
        echo "Response time: $time_total seconds"
        echo "Response size: $size_download bytes"
        echo "Response body: $response_body"
    end

    test "$http_code" = "200"; and begin
        set -q _flag_verbose; and begin
            echo "✓ Message sent successfully!"
            echo "Total time: $time_total seconds"
        end
        return 0
    end

    test $attempt -eq $max_tries; and begin
        echo "Failed to send message after $max_tries attempts (HTTP $http_code)"
        set -q _flag_verbose; and begin
            echo "Final response body: $response_body"
            echo "Total attempts made: $attempt"
        end
        return 1
    end

    set wait_time (math "min($wait_time * 2, $max_wait)")

    set -q _flag_verbose; and begin
        echo "✗ Attempt $attempt failed (HTTP $http_code)"
        echo "Response body: $response_body"
        echo "Waiting $wait_time seconds before retry..."
        echo ""
    end; or echo "Attempt $attempt failed (HTTP $http_code), retrying in $wait_time seconds..."

    sleep $wait_time
    set attempt (math $attempt + 1)
end
