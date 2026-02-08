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

resource "google_secret_manager_secret_iam_member" "hestia_ntfy" {
  project   = var.project_id
  secret_id = "ntfy-basic-auth-password"
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.hestia_backup.email}"
}
