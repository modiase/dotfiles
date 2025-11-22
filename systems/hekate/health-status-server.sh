#!/usr/bin/env bash
set -euo pipefail

SOCKET_PATH="/run/health-status/status.sock"
SCRIPT_PATH="${BASH_SOURCE[0]}"

generate_data() {
    read -r _ user1 nice1 system1 idle1 iowait1 irq1 softirq1 steal1 _ _ </proc/stat || return 1
    sleep 1
    read -r _ user2 nice2 system2 idle2 iowait2 irq2 softirq2 steal2 _ _ </proc/stat || return 1

    local total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1 + steal1))
    local used1=$((user1 + nice1 + system1 + irq1 + softirq1 + steal1))
    local total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2 + steal2))
    local used2=$((user2 + nice2 + system2 + irq2 + softirq2 + steal2))

    local total_delta=$((total2 - total1))
    local used_delta=$((used2 - used1))
    local cpu_percent=0
    if [[ $total_delta -gt 0 ]]; then
        cpu_percent=$((used_delta * 100 / total_delta))
    fi

    local mem_total mem_available mem_used mem_percent
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}') || mem_total=0
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}') || mem_available=0
    mem_used=$((mem_total - mem_available))
    mem_percent=0
    if [[ $mem_total -gt 0 ]]; then
        mem_percent=$((mem_used * 100 / mem_total))
    fi

    local uptime_seconds load1 load5 load15
    uptime_seconds=$(awk '{print int($1)}' /proc/uptime) || uptime_seconds=0
    read -r load1 load5 load15 _ </proc/loadavg || {
        load1="0.00"
        load5="0.00"
        load15="0.00"
    }

    local temp_celsius=0
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        local temp_millidegrees
        temp_millidegrees=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null) || temp_millidegrees=0
        temp_celsius=$((temp_millidegrees / 1000))
    fi

    printf 'CPU_PERCENT:%d\n' "$cpu_percent"
    printf 'MEM_TOTAL_KB:%d\n' "$mem_total"
    printf 'MEM_USED_KB:%d\n' "$mem_used"
    printf 'MEM_AVAILABLE_KB:%d\n' "$mem_available"
    printf 'MEM_PERCENT:%d\n' "$mem_percent"
    printf 'UPTIME_SECONDS:%d\n' "$uptime_seconds"
    printf 'LOAD_AVG_1MIN:%s\n' "$load1"
    printf 'LOAD_AVG_5MIN:%s\n' "$load5"
    printf 'LOAD_AVG_15MIN:%s\n' "$load15"
    printf 'TEMP_CELSIUS:%d\n' "$temp_celsius"
}

if [[ "${1:-}" == "--generate" ]]; then
    generate_data || echo "ERROR: Failed to read system health data"
    exit 0
fi

rm -f "$SOCKET_PATH"

socat UNIX-LISTEN:"$SOCKET_PATH",mode=0666,unlink-early,fork EXEC:"$SCRIPT_PATH --generate"
