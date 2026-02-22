resource "google_service_account" "hestia_backup" {
  account_id   = "hestia-backup-sa"
  display_name = "Hestia Backup Service Account"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "hestia_backup" {
  bucket = var.backups_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.hestia_backup.email}"
}

resource "google_pubsub_topic_iam_member" "hestia_ntfy" {
  project = var.project_id
  topic   = "ntfy"
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.hestia_backup.email}"
}

resource "google_service_account_iam_member" "hestia_wif" {
  service_account_id = google_service_account.hestia_backup.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${var.workload_identity_pool}/subject/hestia"
}
