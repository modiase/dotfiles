OpenTofu Infrastructure Stack
==============================

This directory contains OpenTofu modules that provision the shared Google Cloud
infrastructure for NixOS hosts:

- service accounts (with storage permissions)
- GCS buckets (uniform access, versioning, lifecycle policies)
- firewall rules and static IPs
- compute instances booting from prebuilt NixOS images

Directory Layout
----------------
- `main.tofu` — root stack wiring providers and modules
- `variables.tofu` — input variables (project ID, region/zone, SSH key, bucket, image)
- `outputs.tofu` — useful outputs (public IP, bucket name, service-account email, image self-link)
- `tofu.tfvars.example` — template values to copy into `tofu.tfvars`

Workflow
--------
1. Copy the example variables file:
   ```bash
   cp tofu.tfvars.example tofu.tfvars
   ```
2. Edit `tofu.tfvars` with your project, bucket, and image details.
3. Validate formatting and configuration:
   ```bash
   tofu fmt -check
   tofu validate
   ```
4. When ready to provision:
   ```bash
   tofu plan  -var-file=tofu.tfvars
   tofu apply -var-file=tofu.tfvars
   ```

Instance Boot Flow
------------------
Instances boot from prebuilt NixOS images referenced by `nixos_image_source`.
The image should already include the desired system configuration (users,
services, etc.) so no bootstrap script is required.

Notes
-----
- Service accounts are attached to instances with `devstorage.read_write` scope
  so systemd services (e.g., backups) can talk to GCS without static credentials.
- Buckets use uniform access, versioning, and an age-based lifecycle policy by
  default; adjust via `tofu.tfvars` if needed.
- Firewall rules open TCP 22/80/443. Modify `systems/<host>/configuration.nix`
  for additional ports.

