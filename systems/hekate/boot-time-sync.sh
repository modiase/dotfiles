#!/usr/bin/env bash
set -euo pipefail

timedatectl set-ntp true || {
    echo "Failed to enable NTP, continuing anyway"
    exit 0
}

for _ in {1..25}; do
    if timedatectl status | grep -q "System clock synchronized: yes"; then
        echo "Time synchronized successfully"
        exit 0
    fi
    sleep 1
done

echo "Time sync timeout after 25 seconds, firewall will now be enabled"
exit 0
