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

import {
  to = module.hermes.google_secret_manager_secret.authelia_hmac_secret
  id = "projects/modiase-infra/secrets/authelia-hmac-secret"
}

import {
  to = module.hermes.google_secret_manager_secret.authelia_oidc_jwks_key
  id = "projects/modiase-infra/secrets/authelia-oidc-jwks-key"
}

import {
  to = module.hermes.google_secret_manager_secret.authelia_secrets
  id = "projects/modiase-infra/secrets/authelia-secrets"
}

import {
  to = module.hermes.google_secret_manager_secret.hermes_cert_private_key
  id = "projects/modiase-infra/secrets/hermes-cert-private-key"
}

import {
  to = module.hermes.google_secret_manager_secret.hermes_gmail_address
  id = "projects/modiase-infra/secrets/hermes-gmail-address"
}

import {
  to = module.hermes.google_secret_manager_secret.hermes_gmail_client_id
  id = "projects/modiase-infra/secrets/hermes-gmail-client-id"
}

import {
  to = module.hermes.google_secret_manager_secret.hermes_gmail_client_secret
  id = "projects/modiase-infra/secrets/hermes-gmail-client-secret"
}

import {
  to = module.hermes.google_secret_manager_secret.hermes_gmail_refresh_token
  id = "projects/modiase-infra/secrets/hermes-gmail-refresh-token"
}

import {
  to = module.hermes.google_secret_manager_secret.nvd_api_key
  id = "projects/modiase-infra/secrets/nvd-api-key"
}

import {
  to = module.amex_otp.google_secret_manager_secret.amex_otp_gmail_credentials
  id = "projects/modiase-infra/secrets/amex-otp-gmail-credentials"
}

import {
  to = module.amex_otp.google_secret_manager_secret.amex_credentials
  id = "projects/modiase-infra/secrets/amex-credentials"
}

import {
  to = module.ntfy_pubsub.google_secret_manager_secret.ntfy_basic_auth_password
  id = "projects/modiase-infra/secrets/ntfy-basic-auth-password"
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
  source     = "./modules/workload-identity"
  project_id = var.project_id
  region     = var.backup_bucket_location
  keys       = var.wif_keys
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
  source           = "./modules/gcs-periodic-upload-monitor"
  project_id       = var.project_id
  region           = var.region
  functions_bucket = module.ntfy_pubsub.functions_bucket
  ntfy_topic_id    = module.ntfy_pubsub.topic_id
  ntfy_topic_name  = module.ntfy_pubsub.topic_name

  name          = "hestia-backup"
  bucket        = var.backup_bucket_name
  object        = "hestia/metadata.json"
  schedule      = "0 */6 * * *"
  max_age_hours = 48
  ntfy_topic    = "backups"
  ntfy_priority = "4"
  ntfy_title    = "Backup Alert"
  ntfy_message  = "Expected backup from hestia missing"
}

module "amex_otp" {
  source                 = "./modules/amex-otp"
  project_id             = var.project_id
  region                 = var.region
  workload_identity_pool = module.workload_identity.pool_name
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
