terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "opentofu/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "hermes" {
  source = "../systems/hermes"

  bucket_lifecycle_days = var.bucket_lifecycle_days
  bucket_location       = var.bucket_location
  bucket_name           = var.bucket_name
  machine_type          = var.machine_type
  nixos_image_family    = var.nixos_image_family
  nixos_image_name      = var.nixos_image_name
  nixos_image_source    = var.nixos_image_source
  project_id            = var.project_id
  ssh_public_key        = var.ssh_public_key
  static_ip_name        = var.static_ip_name
  zone                  = var.zone
}
