terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

resource "google_pubsub_topic" "gmail" {
  name    = "gmail-notifications"
  project = var.project_id
}

resource "google_pubsub_topic_iam_member" "gmail_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.gmail.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
}

resource "google_service_account" "gmail_dispatcher" {
  account_id   = "gmail-dispatcher"
  display_name = "Gmail Dispatcher Cloud Function"
  project      = var.project_id
}

data "archive_file" "gmail_dispatcher" {
  type        = "zip"
  source_dir  = "${path.module}/functions/gmail-dispatcher"
  output_path = "${path.module}/.build/gmail-dispatcher.zip"
  excludes    = ["node_modules", "dist", ".build"]
}

resource "google_storage_bucket" "functions" {
  name                        = "${var.project_id}-gmail-dispatcher"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "gmail_dispatcher" {
  name   = "gmail-dispatcher-${data.archive_file.gmail_dispatcher.output_md5}.zip"
  bucket = google_storage_bucket.functions.name
  source = data.archive_file.gmail_dispatcher.output_path
}

resource "google_cloudfunctions2_function" "gmail_dispatcher" {
  name     = "gmail-dispatcher"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "nodejs20"
    entry_point = "handlePubSub"
    source {
      storage_source {
        bucket = google_storage_bucket.functions.name
        object = google_storage_bucket_object.gmail_dispatcher.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.gmail_dispatcher.email
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.gmail.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }
}
