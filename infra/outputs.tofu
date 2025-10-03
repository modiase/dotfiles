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
