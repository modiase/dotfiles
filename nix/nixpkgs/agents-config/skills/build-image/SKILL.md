---
name: build-image
description: Build and deploy NixOS system images (e.g. hermes). Use when deploying NixOS hosts or discussing the build-image workflow.
allowed-tools: [Bash, Read, Grep, Glob]
---

# build-image

Builds immutable NixOS GCE images and optionally deploys them via OpenTofu.

## Key facts

- Builds from the **local working tree** — no commit or push required
- Produces a full NixOS GCE image, uploads to GCS, then runs `tofu apply` to replace the VM
- This is **not** `bin/activate deploy` — that does in-place config switching via SSH
- The build runs on a remote host (default: `herakles`) via Nix remote building

## Usage

```bash
build-image <system> [options] [command]
```

### Commands

| Command   | Description                                        |
|-----------|----------------------------------------------------|
| (default) | Build image and upload to GCS                      |
| `deploy`  | Build, upload, and deploy via OpenTofu              |
| `check`   | Run prerequisite checks only                       |

### Options

| Option              | Description                              |
|---------------------|------------------------------------------|
| `-v` / `--verbose`  | Increase verbosity (stackable)           |
| `--project-id`      | GCP project (default: `modiase-infra`)   |
| `--remote-host`     | Remote Nix builder (default: `herakles`) |
| `--no-build`        | Deploy only (skip image build + upload)  |

### Examples

```bash
build-image hermes -v deploy
build-image hermes deploy --no-build
build-image hermes check
```

### With ntfy notification

```bash
ntfy-me --command 'build-image hermes -v deploy' -t builds
```

## Architecture

1. `bin/build-image` → `nix run .#build-system-image`
2. Dispatches to per-system script (e.g. `build-hermes-image`)
3. System script calls `systems/<name>/build/image` (Python + Click)
4. Build steps: nix build → upload tarball to GCS → tofu apply (on deploy)

## Available systems

Systems with `mkBuildImage` defined in their `systems/<name>/default.nix` are buildable.
