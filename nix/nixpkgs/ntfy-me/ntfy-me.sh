#!/usr/bin/env bash
set +e # Handle errors manually for retry logic

usage() {
    echo "Usage: ntfy-me [OPTIONS] <message>"
    echo ""
    echo "Options:"
    echo "  -a, --alert-type TYPE  Alert type tag (success, warning, error, request)"
    echo "  -c, --command CMD      Run command and report result"
    echo "  -m, --markdown         Enable markdown formatting"
    echo "  --max-tries N          Max retry attempts (default: 3)"
    echo "  --max-wait S           Max wait between retries (default: 300)"
    echo "  -p, --priority N       Priority 1-5 (default: 3)"
    echo "  -R, --recipient HOST   Target recipient hostname (default: all)"
    echo "  -t, --topic TOPIC      Topic to publish to (default: general)"
    echo "  -T, --title TITLE      Notification title"
    echo "  -v, --verbose          Verbose output"
    exit 1
}

topic="general"
title=""
priority=""
alert_type=""
recipient="all"
command=""
markdown=0
verbose=0
max_tries=3
max_wait=300
message=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -a | --alert-type)
            alert_type="$2"
            shift 2
            ;;
        --alert-type=*)
            alert_type="${1#--alert-type=}"
            shift
            ;;
        -t | --topic)
            topic="$2"
            shift 2
            ;;
        --topic=*)
            topic="${1#--topic=}"
            shift
            ;;
        -T | --title)
            title="$2"
            shift 2
            ;;
        --title=*)
            title="${1#--title=}"
            shift
            ;;
        -p | --priority)
            priority="$2"
            shift 2
            ;;
        --priority=*)
            priority="${1#--priority=}"
            shift
            ;;
        -c | --command)
            command="$2"
            shift 2
            ;;
        --command=*)
            command="${1#--command=}"
            shift
            ;;
        -m | --markdown)
            markdown=1
            shift
            ;;
        -v | --verbose)
            verbose=1
            shift
            ;;
        -R | --recipient)
            recipient="$2"
            shift 2
            ;;
        --recipient=*)
            recipient="${1#--recipient=}"
            shift
            ;;
        --max-tries)
            max_tries="$2"
            shift 2
            ;;
        --max-tries=*)
            max_tries="${1#--max-tries=}"
            shift
            ;;
        --max-wait)
            max_wait="$2"
            shift 2
            ;;
        --max-wait=*)
            max_wait="${1#--max-wait=}"
            shift
            ;;
        -h | --help) usage ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            ;;
        *)
            message="$1"
            shift
            ;;
    esac
done

if [[ -n "$command" ]]; then
    start_time=$(date "+%Y-%m-%d %H:%M:%S %Z")
    _hostname=$(hostname)

    if bash -c "$command"; then
        end_time=$(date "+%Y-%m-%d %H:%M:%S %Z")
        message="## ✅ $command

**Host:** $_hostname
**Started:** $start_time
**Finished:** $end_time"
        markdown=1
    else
        end_time=$(date "+%Y-%m-%d %H:%M:%S %Z")
        message="## ❌ $command

**Host:** $_hostname
**Started:** $start_time
**Finished:** $end_time"
        markdown=1
    fi
fi

if [[ -n "$priority" ]] && [[ ! "$priority" =~ ^[1-5]$ ]]; then
    echo "Error: Priority must be 1-5, got: $priority" >&2
    exit 1
fi

if [[ -z "$message" ]]; then
    echo "Error: No message provided" >&2
    usage
fi

[[ $verbose -eq 1 ]] && echo "Sending to topic: $topic"

tags="source-$(hostname -s)"
tags="$tags,recipient-$recipient"
[[ -n "$alert_type" ]] && tags="$tags,type-$alert_type"

attrs="^:^topic=$topic"
attrs="$attrs:priority=${priority:-3}"
[[ -n "$title" ]] && attrs="$attrs:title=$title"
[[ $markdown -eq 1 ]] && attrs="$attrs:markdown=yes"
attrs="$attrs:tags=$tags"

attempt=1
wait_time=1

gcloud_verbosity="warning"
if [[ $verbose -eq 1 ]]; then gcloud_verbosity="debug"; fi

while [[ $attempt -le $max_tries ]]; do
    [[ $verbose -eq 1 ]] && echo "Attempt $attempt/$max_tries..."

    if output=$(gcloud pubsub topics publish ntfy \
        --project=modiase-infra \
        --message="$message" \
        --attribute="$attrs" \
        --verbosity="$gcloud_verbosity" 2>&1); then
        [[ $verbose -eq 1 ]] && echo "$output"
        exit 0
    fi

    if [[ $attempt -eq $max_tries ]]; then
        echo "Failed after $max_tries attempts" >&2
        exit 1
    fi

    echo "Attempt $attempt failed, retrying in ${wait_time}s..." >&2
    sleep "$wait_time"

    wait_time=$((wait_time * 2))
    if [[ $wait_time -gt $max_wait ]]; then wait_time=$max_wait; fi
    attempt=$((attempt + 1))
done
