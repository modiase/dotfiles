output "topic_id" {
  value       = google_pubsub_topic.ntfy.id
  description = "Full Pub/Sub topic ID"
}

output "topic_name" {
  value       = google_pubsub_topic.ntfy.name
  description = "Pub/Sub topic name"
}

output "functions_bucket" {
  value       = google_storage_bucket.functions.name
  description = "GCS bucket for Cloud Function source"
}
