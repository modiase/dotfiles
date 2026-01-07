output "hermes_public_ip" {
  description = "Static public IP of hermes server"
  value       = google_compute_address.hermes_static_ip.address
}

output "hermes_static_ip_name" {
  description = "Name of the static IP resource"
  value       = google_compute_address.hermes_static_ip.name
}

output "hermes_bucket_name" {
  description = "Name of the Hermes GCS bucket"
  value       = google_storage_bucket.hermes.name
}

output "hermes_service_account_email" {
  description = "Service account email attached to Hermes"
  value       = google_service_account.hermes_storage.email
}

output "hermes_nixos_image" {
  description = "Self link of the custom NixOS image used by Hermes"
  value       = google_compute_image.hermes_nixos.self_link
}
