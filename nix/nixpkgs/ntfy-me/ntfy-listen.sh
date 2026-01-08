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

current_host="source-$(hostname -s)"
last_ding=0
log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Starting ntfy-listen (filtering: $current_host)"

while read -r line; do
    [[ "$line" != data:* ]] && continue
    json="${line#data: }"

    topic=$(echo "$json" | jq -r '.topic // "ntfy"')
    title=$(echo "$json" | jq -r ".title // \"$topic\"")
    message=$(echo "$json" | jq -r '.message // empty')
    tags=$(echo "$json" | jq -r '.tags // [] | join(",")')
    msg_time=$(echo "$json" | jq -r '.time // 0')
    now=$(date +%s)
    age=$((now - msg_time))

    log "Received: topic=$topic title=\"$title\" age=${age}s tags=[$tags]"

    if [[ "$tags" == *"$current_host"* ]]; then
        log "  -> Skipped (from self)"
        continue
    fi
    if [[ $age -gt 300 ]]; then
        log "  -> Skipped (too old: ${age}s)"
        continue
    fi
    if [[ $((now - last_ding)) -lt 2 ]]; then
        log "  -> Skipped (debounce)"
        continue
    fi
    last_ding=$now

    if [[ -n "$message" ]]; then
        log "  -> Alert sent"
        ding --local --force -m "$message" --title "$title" >/dev/null
    fi
done < <(curl -sN --proto =https --fail-with-body -u "ntfy:$password" "https://ntfy.modiase.dev/ding,builds,important/sse" 2>/dev/null)
