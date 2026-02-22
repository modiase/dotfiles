output "pool_name" {
  value       = google_iam_workload_identity_pool.machines.name
  description = "Full resource name of the Workload Identity Pool"
}

output "issuer_url" {
  value       = "https://storage.googleapis.com/${google_storage_bucket.oidc.name}"
  description = "OIDC issuer URL for credential configuration"
}

output "provider_id" {
  value       = google_iam_workload_identity_pool_provider.oidc.workload_identity_pool_provider_id
  description = "Workload Identity Pool Provider ID"
}

output "pool_id" {
  value       = google_iam_workload_identity_pool.machines.workload_identity_pool_id
  description = "Workload Identity Pool ID"
}
