#!/usr/bin/env bash
set -euo pipefail

SOCKET_PATH="/run/wg-status/status.sock"
SCRIPT_PATH="${BASH_SOURCE[0]}"

if [[ "${1:-}" == "--generate" ]]; then
    wg show wg0 dump 2>/dev/null | awk 'BEGIN {OFS="\t"} NR==1 {$1="REDACTED"; print; next} {print}' || echo "ERROR: WireGuard interface not available"
    exit 0
fi

rm -f "$SOCKET_PATH"

socat UNIX-LISTEN:"$SOCKET_PATH",mode=0666,unlink-early,fork EXEC:"$SCRIPT_PATH --generate"
