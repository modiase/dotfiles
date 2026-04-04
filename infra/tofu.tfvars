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
    x = "BIZlG7kMCqqHeVGZqxoNa369eJpOETt_w4GunJTQ7nE"
    y = "5GWBuiP7tYlkis7Z3b5N_Y2LuGdnIM0fYu-_xjqOP1g"
  }
  amex-otp = {
    x = "bQO-n66SnpKghxJIgL3VadrygDL0pI60wIkyAOAXhWA"
    y = "0lc9izhfSbO-FZg_SKoxUaBYC0KKMnTmUI_5vz5vqh4"
  }
}
