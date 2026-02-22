output "hermes_public_ip" {
  description = "Public IP of hermes server"
  value       = module.hermes.hermes_public_ip
}

output "hermes_bucket_name" {
  description = "Name of the Hermes GCS bucket"
  value       = module.hermes.hermes_bucket_name
}

output "hermes_service_account_email" {
  description = "Service account email attached to Hermes"
  value       = module.hermes.hermes_service_account_email
}

output "hermes_static_ip_name" {
  description = "Name of the static IP resource"
  value       = module.hermes.hermes_static_ip_name
}

output "hermes_nixos_image" {
  description = "Self link of the custom NixOS image consumed by Hermes"
  value       = module.hermes.hermes_nixos_image
}

output "wif_pool_name" {
  description = "Full resource name of the Workload Identity Pool"
  value       = module.workload_identity.pool_name
}

output "wif_issuer_url" {
  description = "OIDC issuer URL for credential configuration"
  value       = module.workload_identity.issuer_url
}

output "wif_pool_id" {
  description = "Workload Identity Pool ID"
  value       = module.workload_identity.pool_id
}

output "wif_provider_id" {
  description = "Workload Identity Pool Provider ID"
  value       = module.workload_identity.provider_id
}
