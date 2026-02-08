variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "backups_bucket" {
  type        = string
  description = "Name of the GCS bucket for backups"
}
