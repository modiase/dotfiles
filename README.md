# Dotfiles & Infrastructure

This repository contains:

- NixOS system configurations for servers (e.g. Hermes) and remote builders.
- nix-darwin + home-manager configurations for macOS hosts.
- Infrastructure-as-code (OpenTofu) to provision Google Cloud resources for Hermes.
- Helper scripts to build Google Compute Engine images from the Nix flake.

## Building Hermes GCE Images

Use `bin/build-gce-nixos-image.sh` to build and upload a GCE-compatible raw disk
image. The script requires `--attr` to specify which derivation to build. For Hermes,
run:

```
PROJECT_ID=modiase-infra ./bin/build-gce-nixos-image.sh \
  --attr nixosConfigurations.hermes.config.system.build.googleComputeImage \
  --dest gs://modiase-infra/images/hermes-nixos-latest.tar.gz \
  --remote-host herakles
```

This command builds the full Hermes system image, uploads it to Google Cloud Storage,
and writes metadata alongside the tarball. Omitting `--dest` publishes a generic base image at
`gs://modiase-infra/images/base-nixos-latest-x86_64.tar.gz`.

For a combined build + taint + apply workflow (non-interactive `tofu apply -auto-approve`), run:

```
PROJECT_ID=modiase-infra ./bin/build-and-deploy-hermes.sh
```

## Provisioning Hermes

1. Ensure `infra/tofu.tfvars` points `nixos_image_source` to the uploaded tarball (e.g.
   `https://storage.googleapis.com/modiase-infra/images/hermes-nixos-latest.tar.gz`).
2. Run `cd infra && tofu plan -var-file=tofu.tfvars` followed by `tofu apply -var-file=tofu.tfvars`.
3. Terraform creates the image and instance. Hermes boots directly into the NixOS
   configuration (user `moye`, ntfy/n8n services, nginx, backups, dotfiles bootstrap).

## Git Maintenance

Enable background git maintenance (hourly prefetch, commit-graph updates, etc.) in any repo:

```bash
git config --file ~/.config/git/maintenance.config --add maintenance.repo "$(pwd)"
git maintenance start --scheduler=auto
```

The `--file` flag is required because home-manager manages the global git config as read-only. Maintenance settings are stored in `~/.config/git/maintenance.config`, which is included in the global config.

## Agent Workflow Notes

Automations and CI jobs must:

- Always run `bin/activate` before invoking rebuilds or system updates.
- Avoid calling `darwin-rebuild`, `nixos-rebuild`, or `home-manager` directly.
- Treat the repo as source-only; builds and tests run within the activated shell.

Consult `AGENTS.md` for the full guidelines.
