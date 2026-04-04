variable "project_id" {
  type        = string
  description = "GCP Project ID"
}

variable "region" {
  type        = string
  description = "GCP region for bucket"
  default     = "EUROPE-WEST2"
}

variable "keys" {
  type = map(object({
    x = string
    y = string
  }))
  description = "Map of subject ID to ES256 public key coordinates (base64url-encoded)"
}
