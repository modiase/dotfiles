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

my_hostname=$(hostname -s)
current_host="source-$my_hostname"
last_ding=0
log() { echo "[$(date '+%H:%M:%S')] $*"; }

state_dir="$HOME/.local/state/ntfy-listen"
state_file="$state_dir/last-id"
mkdir -p "$state_dir"
last_id=$(cat "$state_file" 2>/dev/null || echo "all")

fifo="/tmp/ntfy-listen-$$"
mkfifo "$fifo"

cleanup() {
    kill "$pid_broadcast" "$pid_targeted" "$pid_watchdog" 2>/dev/null || true
    rm -f "$fifo"
}
trap cleanup EXIT

base_url="https://ntfy.modiase.dev/ding,builds,important/sse"
curl -sN --proto =https --fail-with-body -u "ntfy:$password" "$base_url?tags=recipient-*&since=$last_id" >"$fifo" 2>/dev/null &
pid_broadcast=$!
curl -sN --proto =https --fail-with-body -u "ntfy:$password" "$base_url?tags=recipient-$my_hostname&since=$last_id" >"$fifo" 2>/dev/null &
pid_targeted=$!

(
    while kill -0 "$pid_broadcast" 2>/dev/null && kill -0 "$pid_targeted" 2>/dev/null; do sleep 5; done
    kill $$ 2>/dev/null
) &
pid_watchdog=$!

log "Starting ntfy-listen (host=$my_hostname, since=$last_id)"

while read -r line; do
    [[ "$line" != data:* ]] && continue
    json="${line#data: }"

    msg_id=$(echo "$json" | jq -r '.id // empty')
    topic=$(echo "$json" | jq -r '.topic // "ntfy"')
    title=$(echo "$json" | jq -r ".title // \"$topic\"")
    message=$(echo "$json" | jq -r '.message // empty')
    tags=$(echo "$json" | jq -r '.tags // [] | join(",")')
    msg_time=$(echo "$json" | jq -r '.time // 0')
    now=$(date +%s)
    age=$((now - msg_time))

    log "Received: id=$msg_id topic=$topic title=\"$title\" age=${age}s tags=[$tags]"

    [[ -n "$msg_id" ]] && echo "$msg_id" >"$state_file"

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
        source_host="unknown"
        [[ "$tags" =~ source-([^,]+) ]] && source_host="${BASH_REMATCH[1]}"
        ding_args=(--local -f -w "Remote: $source_host" -i "$title" -m "$message")
        if [[ "$tags" =~ type-([a-z]+) ]]; then
            ding_args+=(-t "${BASH_REMATCH[1]}")
        fi
        ding "${ding_args[@]}" >/dev/null
    fi
done <"$fifo"
