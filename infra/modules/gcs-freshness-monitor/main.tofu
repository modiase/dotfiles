terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

resource "google_service_account" "monitor" {
  account_id   = "${var.name}-monitor"
  display_name = "${var.name} GCS Freshness Monitor"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "reader" {
  bucket = var.bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.monitor.email}"
}

resource "google_pubsub_topic_iam_member" "publisher" {
  project = var.project_id
  topic   = var.ntfy_topic_name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.monitor.email}"
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/.build/${var.name}.zip"
  excludes    = ["node_modules", "dist", ".build"]
}

resource "google_storage_bucket_object" "function" {
  name   = "${var.name}-${data.archive_file.function.output_md5}.zip"
  bucket = var.functions_bucket
  source = data.archive_file.function.output_path
}

resource "google_cloudfunctions2_function" "monitor" {
  name     = "${var.name}-monitor"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "nodejs20"
    entry_point = "checkFreshness"
    source {
      storage_source {
        bucket = var.functions_bucket
        object = google_storage_bucket_object.function.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.monitor.email
    environment_variables = {
      NTFY_TOPIC_ID = var.ntfy_topic_id
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.monitor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.monitor.email}"
}

resource "google_cloud_scheduler_job" "check" {
  name      = "check-${var.name}"
  project   = var.project_id
  region    = var.region
  schedule  = var.schedule
  time_zone = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.monitor.url
    oidc_token {
      service_account_email = google_service_account.monitor.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode({
      bucket        = var.bucket
      object        = var.object
      max_age_hours = var.max_age_hours
      alert = {
        topic    = var.ntfy_topic
        priority = var.ntfy_priority
        title    = var.ntfy_title
        message  = var.ntfy_message
      }
    }))
  }
}
