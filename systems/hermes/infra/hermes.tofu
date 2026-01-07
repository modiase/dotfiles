terraform {
  required_providers {
    google = {
      source = "opentofu/google"
    }
  }
}

resource "google_service_account" "hermes_storage" {
  account_id   = "hermes-storage"
  display_name = "Hermes Storage Service Account"
}

resource "google_storage_bucket" "hermes" {
  name                        = var.bucket_name
  location                    = var.bucket_location
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = var.bucket_lifecycle_days
    }
    action {
      type = "Delete"
    }
  }

  versioning {
    enabled = true
  }
}

resource "google_storage_bucket_iam_member" "hermes_sa_object_admin" {
  bucket = google_storage_bucket.hermes.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.hermes_storage.email}"
}

resource "google_project_iam_member" "hermes_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.hermes_storage.email}"
}


resource "google_compute_address" "hermes_static_ip" {
  name = var.static_ip_name
}

resource "google_compute_firewall" "hermes" {
  name    = "hermes-services"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["hermes"]
}

resource "google_compute_image" "hermes_nixos" {
  name   = var.nixos_image_name
  family = var.nixos_image_family

  raw_disk {
    source = var.nixos_image_source
  }
}

resource "google_compute_instance" "hermes" {
  name         = "hermes"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["hermes"]

  boot_disk {
    initialize_params {
      image = google_compute_image.hermes_nixos.self_link
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    network = "default"
    access_config {
      nat_ip = google_compute_address.hermes_static_ip.address
    }
  }

  service_account {
    email  = google_service_account.hermes_storage.email
    scopes = [
      "https://www.googleapis.com/auth/devstorage.read_write",
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  metadata = {
    ssh-keys = "nixos:${var.ssh_public_key}"
  }
}
