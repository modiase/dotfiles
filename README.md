# Dotfiles & Infrastructure

This repository contains:

- NixOS system configurations for servers (e.g. Hermes) and remote builders.
- nix-darwin + home-manager configurations for macOS hosts.
- Infrastructure-as-code (OpenTofu) to provision Google Cloud resources for Hermes.
- Helper scripts to build Google Compute Engine images from the Nix flake.

## Building and Deploying Hermes

The `bin/build-hermes` tool provides a complete workflow for building and deploying Hermes:

**Build + Upload + Deploy (recommended):**
```bash
./bin/build-hermes deploy
```

This builds the GCE image on herakles, uploads it to GCS, taints the Terraform resources, and runs `tofu apply -auto-approve` to recreate the instance with the new image.

**Build + Upload only:**
```bash
./bin/build-hermes build
```

Builds the image and uploads to `gs://modiase-infra/images/hermes-nixos-latest.tar.gz` without deploying.

**Deploy only (skip build):**
```bash
./bin/build-hermes deploy --no-build
```

Uses the existing image in GCS and redeploys the instance.

**Check prerequisites:**
```bash
./bin/build-hermes check
```

Validates Nix flake, Terraform config, gcloud auth, and SSH access to herakles.

**Options:**
- `-v` / `-vv` - Increase verbosity
- `--project-id` - Override GCP project (default: modiase-infra)
- `--remote-host` - Override build host (default: herakles)

## Git Maintenance

Enable background git maintenance (hourly prefetch, commit-graph updates, etc.) in any repo:

```bash
git config --file ~/.config/git/maintenance.config --add maintenance.repo "$(pwd)"
git maintenance start --scheduler=auto
```

The `--file` flag is required because home-manager manages the global git config as read-only. Maintenance settings are stored in `~/.config/git/maintenance.config`, which is included in the global config.

## Viewing Activation Logs

**Linux (systemd journal):**
```bash
journalctl -t dotfiles-activate -f
```

**macOS:**
```bash
tail -f ~/Library/Logs/dotfiles-activate.log
```

## Agent Workflow Notes

Automations and CI jobs must:

- Always run `bin/activate` before invoking rebuilds or system updates.
- Avoid calling `darwin-rebuild`, `nixos-rebuild`, or `home-manager` directly.
- Treat the repo as source-only; builds and tests run within the activated shell.

Consult `AGENTS.md` for the full guidelines.
