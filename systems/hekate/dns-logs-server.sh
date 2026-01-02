#!/usr/bin/env bash
set -euo pipefail

SOCKET_PATH="/run/dns-logs/logs.sock"
SCRIPT_PATH="${BASH_SOURCE[0]}"

if [[ "${1:-}" == "--generate" ]]; then
    journalctl -u unbound -n 100 --no-pager -o short-iso 2>/dev/null || echo "ERROR: Unable to read unbound logs"
    exit 0
fi

rm -f "$SOCKET_PATH"

socat UNIX-LISTEN:"$SOCKET_PATH",mode=0666,unlink-early,fork EXEC:"$SCRIPT_PATH --generate"
