project_id            = "modiase-infra"
region                = "europe-west2"
zone                  = "europe-west2-a"
ssh_public_key        = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDeCxppO+Wwy210oH3TXrrnfUxdgIQtKjqos4tqSMV2e moye@pallas"
bucket_name           = "modiase-infra-hermes"
bucket_location       = "EUROPE-WEST2"
bucket_lifecycle_days = 90
nixos_image_name      = "hermes-nixos"
nixos_image_family    = "hermes-nixos"
nixos_image_source    = "https://storage.googleapis.com/modiase-infra/images/hermes-nixos-latest.tar.gz"

wif_keys = {
  hestia = {
    x = "2bJVh1i8qPrcTvk-_c6EK7jZN0MgbXrMNe2oZ3KYY5c"
    y = "rztZlti4vzhqKpxAk049eZ1nhKWEzbIhMdwnX_J-W0g"
  }
  amex-otp = {
    x = "bQO-n66SnpKghxJIgL3VadrygDL0pI60wIkyAOAXhWA"
    y = "0lc9izhfSbO-FZg_SKoxUaBYC0KKMnTmUI_5vz5vqh4"
  }
}
