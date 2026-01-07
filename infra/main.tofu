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
  source = "../systems/hermes/infra"

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

resource "google_storage_bucket" "backups" {
  name                        = var.backup_bucket_name
  location                    = var.backup_bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.backup_retention_days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }
}
