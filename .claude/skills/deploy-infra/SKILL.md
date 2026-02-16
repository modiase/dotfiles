---
name: deploy-infra
description: Deploy GCP infrastructure using OpenTofu. Use when working with infra/ directory or .tofu files.
allowed-tools: Bash(bin/deploy-infra*)
---

# Infrastructure Deployment (OpenTofu)

GCP infrastructure is managed with OpenTofu in `infra/`. Use `bin/deploy-infra` to deploy.

## Commands

| Command | Description |
|---------|-------------|
| `bin/deploy-infra` | Plan and apply with confirmation prompt |
| `bin/deploy-infra -y` | Auto-approve (no confirmation) |
| `bin/deploy-infra -f` | Force unlock stale state lock before planning |
| `bin/deploy-infra -a` | Upgrade providers before planning |
| `bin/deploy-infra -p PROJECT` | Use different GCP project (default: modiase-infra) |

## Module Structure

```
infra/
├── main.tofu           # Root module
├── variables.tofu      # Input variables
├── outputs.tofu        # Exported values
├── tofu.tfvars         # Variable values (gitcrypted)
└── modules/
    ├── ntfy-pubsub/
    ├── gmail-dispatcher/
    ├── hestia/
    └── ...
```

## Important

- **Do NOT run `tofu` directly** - the wrapper handles init and tooling
- **Do NOT deploy without explicit user request** - changes can be destructive
- **State stored in GCS**: `gs://modiase-infra-tofu-state/infra`
- **Force unlock sparingly** - only when certain lock is stale

## Task

$ARGUMENTS
