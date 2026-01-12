# Dotfiles & Infrastructure

```bash
git clone git@github.com:modiase/Dotfiles.git ~/Dotfiles
cd ~/Dotfiles
bin/bootstrap
source ~/.nix-profile/etc/profile.d/nix.sh
bin/activate -s <hostname>
```

## Encrypted Configurations

Some system configurations (hephaistos, hekate) are encrypted with git-crypt. After cloning, these files appear as binary blobs until unlocked.

**Unlock (requires the key file):**
```bash
git-crypt unlock /path/to/git-crypt-key
```

**Check encryption status:**
```bash
git-crypt status
```

Files remain plaintext locally once unlocked. Encryption is transparent on commit/push.

---

This repository contains:

- NixOS system configurations for servers (e.g. Hermes) and remote builders.
- nix-darwin + home-manager configurations for macOS hosts.
- Infrastructure-as-code (OpenTofu) to provision Google Cloud resources for Hermes.
- Helper scripts to build Google Compute Engine images from the Nix flake.

## Building System Images

The `bin/build-image` tool provides a unified workflow for building system images:

```bash
./bin/build-image           # Select system interactively with gum
./bin/build-image hermes    # Build hermes directly
```

System-specific build scripts are located at `systems/<name>/build/image`.

**Hermes example (GCE image):**
```bash
./bin/build-image hermes deploy        # Build + Upload + Deploy
./bin/build-image hermes build         # Build + Upload only
./bin/build-image hermes deploy --no-build  # Deploy existing image
./bin/build-image hermes check         # Validate prerequisites
```

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
