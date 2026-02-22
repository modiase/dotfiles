variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "europe-west2" # London
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "europe-west2-a"
}

variable "ssh_public_key" {
  description = "SSH public key for access"
  type        = string
}

variable "bucket_name" {
  description = "Name of the single GCS bucket for Hermes"
  type        = string
}

variable "bucket_location" {
  description = "Location/region for the GCS bucket"
  type        = string
  default     = "EUROPE-WEST2"
}

variable "bucket_lifecycle_days" {
  description = "Days after which to delete old objects"
  type        = number
  default     = 90
}

variable "static_ip_name" {
  description = "Name for the static IP address"
  type        = string
  default     = "hermes-static-ip"
}

variable "nixos_image_name" {
  description = "Name for the custom NixOS compute image"
  type        = string
  default     = "hermes-nixos"
}

variable "nixos_image_family" {
  description = "Image family label for the custom NixOS image"
  type        = string
  default     = "hermes-nixos"
}

variable "nixos_image_source" {
  description = "gs:// URI for the raw disk tarball produced by the NixOS GCE image build"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type for the instance"
  type        = string
  default     = "e2-small"
}

variable "backup_bucket_name" {
  type    = string
  default = "modiase-backups"
}

variable "backup_bucket_location" {
  type    = string
  default = "EUROPE-WEST2"
}

variable "backup_retention_days" {
  type    = number
  default = 90
}

variable "wif_machine_keys" {
  type = map(object({
    x = string
    y = string
  }))
  description = "Map of machine ID to ES256 public key coordinates (base64url-encoded)"
  default     = {}
}
