terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

resource "google_service_account" "backup_monitor" {
  account_id   = "backup-monitor"
  display_name = "Backup Monitor"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "backup_monitor_reader" {
  bucket = var.backups_bucket
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.backup_monitor.email}"
}

resource "google_pubsub_topic_iam_member" "backup_monitor_publisher" {
  project = var.project_id
  topic   = var.ntfy_topic_name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.backup_monitor.email}"
}

resource "google_cloud_run_v2_service_iam_member" "backup_monitor_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.backup_monitor.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.backup_monitor.email}"
}

data "archive_file" "backup_monitor" {
  type        = "zip"
  source_dir  = "${path.module}/functions/backup-monitor"
  output_path = "${path.module}/.build/backup-monitor.zip"
  excludes    = ["node_modules", "dist", ".build"]
}

resource "google_storage_bucket_object" "backup_monitor" {
  name   = "backup-monitor-${data.archive_file.backup_monitor.output_md5}.zip"
  bucket = var.functions_bucket
  source = data.archive_file.backup_monitor.output_path
}

resource "google_cloudfunctions2_function" "backup_monitor" {
  name     = "backup-monitor"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "nodejs20"
    entry_point = "checkBackup"
    source {
      storage_source {
        bucket = var.functions_bucket
        object = google_storage_bucket_object.backup_monitor.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.backup_monitor.email
    environment_variables = {
      NTFY_TOPIC_ID = var.ntfy_topic_id
      PROJECT_ID    = var.project_id
    }
  }
}

resource "google_cloud_scheduler_job" "backup_check" {
  name      = "check-hestia-backup"
  project   = var.project_id
  region    = var.region
  schedule  = "0 */6 * * *"
  time_zone = "UTC"

  http_target {
    http_method = "POST"
    uri         = google_cloudfunctions2_function.backup_monitor.url
    oidc_token {
      service_account_email = google_service_account.backup_monitor.email
    }
    headers = {
      "Content-Type" = "application/json"
    }
    body = base64encode(jsonencode({
      bucket        = var.backups_bucket
      object        = "hestia/metadata.json"
      max_age_hours = 48
      alert = {
        topic    = "backups"
        priority = "1"
        title    = "Backup Alert"
        message  = "Expected backup from hestia missing"
      }
    }))
  }
}
