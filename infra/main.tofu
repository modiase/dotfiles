terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "opentofu/google"
      version = "~> 5.0"
    }
  }
  backend "gcs" {
    bucket = "modiase-infra-tofu-state"
    prefix = "infra"
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

module "workload_identity" {
  source       = "./modules/workload-identity"
  project_id   = var.project_id
  region       = var.backup_bucket_location
  machine_keys = var.wif_machine_keys
}

module "hestia" {
  source                 = "./modules/hestia"
  project_id             = var.project_id
  backups_bucket         = var.backup_bucket_name
  workload_identity_pool = module.workload_identity.pool_name
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

module "ntfy_pubsub" {
  source     = "./modules/ntfy-pubsub"
  project_id = var.project_id
  region     = var.region
}

module "gmail_dispatcher" {
  source     = "./modules/gmail-dispatcher"
  project_id = var.project_id
  region     = var.region
}

module "hestia_backup_monitor" {
  source           = "./modules/gcs-freshness-monitor"
  project_id       = var.project_id
  region           = var.region
  functions_bucket = module.ntfy_pubsub.functions_bucket
  ntfy_topic_id    = module.ntfy_pubsub.topic_id
  ntfy_topic_name  = module.ntfy_pubsub.topic_name

  name          = "hestia-backup"
  bucket        = var.backup_bucket_name
  object        = "hestia/metadata.json"
  schedule      = "0 0 */2 * *"
  max_age_hours = 48
  ntfy_topic    = "backups"
  ntfy_priority = "1"
  ntfy_title    = "Backup Alert"
  ntfy_message  = "Expected backup from hestia missing"
}

module "cve_monitor" {
  source        = "./modules/cve-monitor"
  project_id    = var.project_id
  ntfy_topic_id = module.ntfy_pubsub.topic_id
}

resource "google_pubsub_topic_iam_member" "hermes_publisher" {
  project = var.project_id
  topic   = module.ntfy_pubsub.topic_name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${module.hermes.hermes_service_account_email}"
}
