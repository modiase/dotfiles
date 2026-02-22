---
name: build-image
description: Build NixOS SD card or GCE images for physical/cloud systems. Use when building system images.
allowed-tools: Bash(bin/build-image*), Bash(build-image*)
---

# Image Building

Use `bin/build-image` or `build-image` to build NixOS images for deployment.

## Supported Systems

| System | Type | Nix Attribute |
|--------|------|---------------|
| hekate | SD card (aarch64) | `nixosConfigurations.hekate.config.system.build.sdImage` |
| hermes | GCE tarball (x86_64) | `nixosConfigurations.hermes.config.system.build.googleComputeImage` |
| hestia | SD card (aarch64) | `nixosConfigurations.hestia.config.system.build.sdImage` |

## Commands

```bash
# Interactive system selection
build-image

# Build specific system
build-image hekate
build-image hermes
build-image hestia

# Hermes-specific (GCE)
build-image hermes deploy              # Build, upload to GCS, terraform deploy
build-image hermes deploy --no-build   # Redeploy existing image

# Hestia with flashing
build-image hestia -d /dev/diskX       # Build and flash to device

# Common options
build-image <system> --remote-host herakles   # Build on remote host
build-image <system> --verify                  # Check prerequisites only
build-image <system> -v                        # Verbose output
```

## Remote Building

All builds support `--remote-host herakles` for cross-architecture builds (e.g., building aarch64 images on x86_64).

## Flashing Safety

SD card flashing (`-d` flag) validates:
- Device exists and is a block device
- Device is removable/external (safety check)
- Uses `diskutil` on macOS, `/sys/block` on Linux

## Key Gotchas

- macOS `dd` returns exit code 1 on success (file close quirk) - handled in scripts
- Images are zstd-compressed (`.img.zst` for SD, `.tar.gz` for GCE)
- hermes uploads to `gs://modiase-infra/images/hermes-nixos-latest.tar.gz`

## Task

$ARGUMENTS
