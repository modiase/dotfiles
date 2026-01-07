#!/usr/bin/env bash
set -eu
password=$(secrets get ntfy-basic-auth-password 2>/dev/null)
if [[ -z "$password" ]]; then
    password=$(secrets get ntfy-basic-auth-password --network 2>/dev/null)
    if [[ -z "$password" ]]; then
        echo "No password" >&2
        exit 1
    fi
    secrets store ntfy-basic-auth-password "$password" --force 2>/dev/null || true
fi

curl -sN --proto =https --fail-with-body -u "ntfy:$password" "https://ntfy.modiase.dev/ding,builds,important/sse" 2>/dev/null | while read -r line; do
    [[ "$line" != data:* ]] && continue
    json="${line#data: }"

    message=$(echo "$json" | jq -r '.message // empty')
    topic=$(echo "$json" | jq -r '.topic // "ntfy"')
    title=$(echo "$json" | jq -r ".title // \"$topic\"")

    if [[ -n "$message" ]]; then ding --force --alert --message "$message" --title "$title" >/dev/null; fi
done
