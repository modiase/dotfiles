terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

resource "google_pubsub_topic" "ntfy" {
  name    = "ntfy"
  project = var.project_id
}

resource "google_storage_bucket" "functions" {
  name                        = "${var.project_id}-functions"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
}

data "archive_file" "ntfy_forwarder" {
  type        = "zip"
  source_dir  = "${path.module}/functions/ntfy-forwarder"
  output_path = "${path.module}/.build/ntfy-forwarder.zip"
  excludes    = ["node_modules", "dist", ".build"]
}

resource "google_storage_bucket_object" "ntfy_forwarder" {
  name   = "ntfy-forwarder-${data.archive_file.ntfy_forwarder.output_md5}.zip"
  bucket = google_storage_bucket.functions.name
  source = data.archive_file.ntfy_forwarder.output_path
}

resource "google_service_account" "ntfy_forwarder" {
  account_id   = "ntfy-forwarder"
  display_name = "ntfy Forwarder Cloud Function"
  project      = var.project_id
}

resource "google_secret_manager_secret_iam_member" "ntfy_password" {
  project   = var.project_id
  secret_id = "ntfy-basic-auth-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.ntfy_forwarder.email}"
}

resource "google_cloudfunctions2_function" "ntfy_forwarder" {
  name     = "ntfy-forwarder"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "nodejs20"
    entry_point = "handlePubSub"
    source {
      storage_source {
        bucket = google_storage_bucket.functions.name
        object = google_storage_bucket_object.ntfy_forwarder.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.ntfy_forwarder.email

    secret_environment_variables {
      key        = "NTFY_PASSWORD"
      project_id = var.project_id
      secret     = "ntfy-basic-auth-password"
      version    = "latest"
    }

    environment_variables = {
      NTFY_URL  = "https://ntfy.modiase.dev"
      NTFY_USER = "ntfy"
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.ntfy.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}
