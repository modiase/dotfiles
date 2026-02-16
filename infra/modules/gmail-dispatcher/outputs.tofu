output "topic_name" {
  description = "Full topic name for Gmail API watch call"
  value       = google_pubsub_topic.gmail.id
}

output "topic_short_name" {
  description = "Short topic name"
  value       = google_pubsub_topic.gmail.name
}
