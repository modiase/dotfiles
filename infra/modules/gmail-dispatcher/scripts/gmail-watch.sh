#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${GMAIL_WATCH_PROJECT:-modiase-infra}"
TOPIC_NAME="projects/${PROJECT_ID}/topics/gmail-notifications"

usage() {
    cat <<EOF
Usage: $(basename "$0") <command>

Commands:
  start   Start watching for Gmail notifications
  stop    Stop watching
  renew   Renew the watch (same as start)
  status  Check current watch status

Requires: gcloud auth with Gmail API scope
  gcloud auth login --enable-gdrive-access
EOF
}

get_token() {
    gcloud auth print-access-token 2>/dev/null || {
        echo "Error: Not authenticated. Run: gcloud auth login --enable-gdrive-access" >&2
        exit 1
    }
}

watch_start() {
    local token
    token=$(get_token)

    echo "Starting Gmail watch on topic: ${TOPIC_NAME}"
    curl -sS -X POST "https://gmail.googleapis.com/gmail/v1/users/me/watch" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{\"topicName\":\"${TOPIC_NAME}\",\"labelIds\":[\"INBOX\"]}" | jq .
}

watch_stop() {
    local token
    token=$(get_token)

    echo "Stopping Gmail watch"
    curl -sS -X POST "https://gmail.googleapis.com/gmail/v1/users/me/stop" \
        -H "Authorization: Bearer ${token}"
    echo "Watch stopped"
}

case "${1:-}" in
    start | renew)
        watch_start
        ;;
    stop)
        watch_stop
        ;;
    status)
        echo "No status endpoint available. Check Cloud Function logs:"
        echo "  gcloud functions logs read gmail-dispatcher --gen2 --region=europe-west2"
        ;;
    *)
        usage
        exit 1
        ;;
esac
