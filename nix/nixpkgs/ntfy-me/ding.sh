#!/usr/bin/env bash
set -eu

mode=""
title="Notification"
message=""
force=0
use_alert=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --remote)
            mode="remote"
            shift
            ;;
        --local)
            mode="local"
            shift
            ;;
        --force)
            force=1
            shift
            ;;
        --alert)
            use_alert=1
            shift
            ;;
        --title)
            title="$2"
            shift 2
            ;;
        --title=*)
            title="${1#--title=}"
            shift
            ;;
        -m | --message)
            message="$2"
            shift 2
            ;;
        --message=*)
            message="${1#--message=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            shift
            ;;
    esac
done

if [[ -z "$mode" ]]; then
    if command -v osascript &>/dev/null; then
        mode="local"
    else
        mode="remote"
    fi
fi

if [[ "$mode" == "local" ]]; then
    if ! command -v osascript &>/dev/null; then
        echo "Error: --local requires macOS (osascript not found)" >&2
        exit 1
    fi
    frontmost=$(osascript -e 'tell application "System Events" to name of (first process whose frontmost is true)')
    if [[ "$frontmost" != "Ghostty" || $force -eq 1 ]]; then
        afplay /System/Library/Sounds/Glass.aiff &
        if [[ -n "$message" ]]; then
            if [[ $use_alert -eq 1 || "$frontmost" != "Ghostty" ]]; then
                osascript -e 'tell application "System Events" to activate' -e "display alert \"$title\" message \"$message\"" &
            else
                osascript -e "display notification \"$message\" with title \"$title\""
            fi
        fi
    fi
else
    if [[ -z "$message" ]]; then
        echo "Warning: --remote without --message does nothing" >&2
        exit 0
    fi
    ntfy-me --topic ding --title "$title" "$message"
fi
