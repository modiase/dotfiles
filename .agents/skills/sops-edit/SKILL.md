---
name: sops-edit
description: Edit SOPS-encrypted secrets files from any machine. Use when modifying secrets.yaml files.
allowed-tools: Bash(just sops-edit *)
---

# SOPS Secrets Editing

Systems have `secrets.yaml` files encrypted with machine-specific age keys. A shared "dotfiles" age key in GCP Secret Manager (as `dotfiles-age-key`) allows decryption from any authenticated machine.

## Usage

```bash
just sops-edit systems/<host>/secrets.yaml
just sops-edit --set '["key-name"] "value"' systems/<host>/secrets.yaml
```

## Adding a New System's Secrets

1. Add the system's age public key as an anchor in `.sops.yaml`
2. Add a `creation_rules` entry with both the system key and `*dotfiles`
3. On the target machine, run `sops updatekeys` to re-encrypt with the new recipient

## Key Files

- `.sops.yaml` — recipient configuration
- `systems/*/secrets.yaml` — encrypted secrets
- `justfile` — `sops-edit` recipe

## Task

$ARGUMENTS
