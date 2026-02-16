# Gmail Dispatcher

Receives Gmail push notifications via Pub/Sub and dispatches them for processing.

## Architecture

```
Gmail API → Pub/Sub Topic → Cloud Function → (future: automation logic)
```

1. Gmail API publishes notifications to `gmail-notifications` Pub/Sub topic
2. Cloud Function receives the notification with `historyId`
3. Currently logs the notification; future: fetch email details and trigger automation

## Setup

### Prerequisites

1. Deploy the infrastructure:
   ```bash
   cd infra && tofu apply
   ```

2. Enable Gmail API in your GCP project:
   ```bash
   gcloud services enable gmail.googleapis.com
   ```

3. Authenticate with Gmail scope:
   ```bash
   gcloud auth login --enable-gdrive-access
   ```

### Start Watching

```bash
./scripts/gmail-watch.sh start
```

This calls the Gmail API `users.watch` endpoint to begin receiving notifications.

### Stop Watching

```bash
./scripts/gmail-watch.sh stop
```

## Watch Expiry

Gmail watches expire after **7 days**. You must renew before expiry:

```bash
./scripts/gmail-watch.sh renew
```

Future enhancement: Add Cloud Scheduler to auto-renew.

## Notification Format

Gmail sends notifications in this format:

```json
{
  "emailAddress": "user@gmail.com",
  "historyId": "12345678"
}
```

The `historyId` is a cursor - to get actual email content, call:

```
GET /gmail/v1/users/me/history?startHistoryId={previousHistoryId}
```

## Logs

View Cloud Function logs:

```bash
gcloud functions logs read gmail-dispatcher --gen2 --region=europe-west2
```

## References

- [Gmail Push Notifications](https://developers.google.com/workspace/gmail/api/guides/push)
- [users.watch API](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users/watch)
- [History API](https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.history/list)
