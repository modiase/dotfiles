#!/usr/bin/env bash
set -euo pipefail

keychain_service="EXA_API_KEY"
user="${USER:-$(whoami)}"

if ! /usr/bin/security find-generic-password -s "$keychain_service" -a "$user" >/dev/null 2>&1; then
    echo "EXA_API_KEY not found in keychain (service=$keychain_service, account=$user)" >&2
    exit 1
fi

export EXA_API_KEY
EXA_API_KEY=$(/usr/bin/security find-generic-password -s "$keychain_service" -a "$user" -w)

exec pnpm dlx exa-mcp-server "$@"
