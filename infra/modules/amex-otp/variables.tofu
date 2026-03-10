variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for resources"
}

variable "workload_identity_pool" {
  type        = string
  description = "Full resource name of the Workload Identity Pool"
}
