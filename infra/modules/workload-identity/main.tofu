resource "google_storage_bucket" "oidc" {
  project                     = var.project_id
  name                        = "${var.project_id}-workload-identity"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "inherited"
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.oidc.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "openid_config" {
  name   = ".well-known/openid-configuration"
  bucket = google_storage_bucket.oidc.name
  content = jsonencode({
    issuer                                = "https://storage.googleapis.com/${google_storage_bucket.oidc.name}"
    jwks_uri                              = "https://storage.googleapis.com/${google_storage_bucket.oidc.name}/jwks.json"
    response_types_supported              = ["id_token"]
    subject_types_supported               = ["public"]
    id_token_signing_alg_values_supported = ["ES256"]
  })
  content_type = "application/json"
}

resource "google_storage_bucket_object" "jwks" {
  name   = "jwks.json"
  bucket = google_storage_bucket.oidc.name
  content = jsonencode({
    keys = [
      for id, key in var.machine_keys : {
        kty = "EC"
        crv = "P-256"
        alg = "ES256"
        use = "sig"
        kid = id
        x   = key.x
        y   = key.y
      }
    ]
  })
  content_type = "application/json"
}

resource "google_iam_workload_identity_pool" "machines" {
  workload_identity_pool_id = "machine-identity"
  display_name              = "Machine Identity Pool"
  description               = "Pool for ES256 key-based machine authentication"
  project                   = var.project_id
}

resource "google_iam_workload_identity_pool_provider" "oidc" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.machines.workload_identity_pool_id
  workload_identity_pool_provider_id = "machine-oidc"
  display_name                       = "Machine OIDC Provider"
  project                            = var.project_id

  oidc {
    issuer_uri = "https://storage.googleapis.com/${google_storage_bucket.oidc.name}"
  }

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
}
