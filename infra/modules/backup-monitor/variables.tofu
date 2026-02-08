variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  default     = "europe-west2"
  description = "GCP Region"
}

variable "backups_bucket" {
  type        = string
  description = "Name of the GCS bucket containing backups"
}

variable "ntfy_topic_id" {
  type        = string
  description = "Full Pub/Sub topic ID for ntfy notifications"
}

variable "ntfy_topic_name" {
  type        = string
  description = "Pub/Sub topic name for ntfy notifications"
}

variable "functions_bucket" {
  type        = string
  description = "GCS bucket for Cloud Function source"
}
