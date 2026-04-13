terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

resource "google_service_account" "amex_otp" {
  account_id   = "amex-otp"
  display_name = "Amex OTP Cloud Function"
  project      = var.project_id
}

resource "google_secret_manager_secret" "amex_otp_gmail_credentials" {
  project   = var.project_id
  secret_id = "amex-otp-gmail-credentials"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret" "amex_credentials" {
  project   = var.project_id
  secret_id = "amex-credentials"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "gmail_credentials" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.amex_otp_gmail_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.amex_otp.email}"
}

resource "google_secret_manager_secret_iam_member" "amex_credentials_invoker" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.amex_credentials.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.invoker.email}"
}

resource "google_storage_bucket" "functions" {
  name                        = "${var.project_id}-amex-otp"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
}

data "archive_file" "function" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/.build/amex-otp.zip"
  excludes    = ["node_modules", "dist", ".build"]
}

resource "google_storage_bucket_object" "function" {
  name   = "amex-otp-${data.archive_file.function.output_md5}.zip"
  bucket = google_storage_bucket.functions.name
  source = data.archive_file.function.output_path
}

resource "google_cloudfunctions2_function" "amex_otp" {
  name     = "amex-otp"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "nodejs20"
    entry_point = "getOtp"
    source {
      storage_source {
        bucket = google_storage_bucket.functions.name
        object = google_storage_bucket_object.function.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 150
    service_account_email = google_service_account.amex_otp.email
    environment_variables = {
      GCP_PROJECT = var.project_id
      GMAIL_QUERY = "subject:\"American Express One-Time Verification Code\" newer_than:5m"
    }
  }
}

resource "google_service_account" "invoker" {
  account_id   = "amex-otp-invoker"
  display_name = "Amex OTP Invoker"
  project      = var.project_id
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloudfunctions2_function.amex_otp.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.invoker.email}"
}

resource "google_service_account_iam_member" "invoker_wif" {
  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${var.workload_identity_pool}/subject/amex-otp"
}

resource "google_secret_manager_secret" "session_cookies" {
  project   = var.project_id
  secret_id = "amex-session-cookies"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_iam_member" "session_cookies_invoker" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.session_cookies.secret_id
  role      = "roles/secretmanager.secretVersionAdder"
  member    = "serviceAccount:${google_service_account.invoker.email}"
}
