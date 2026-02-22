---
name: secrets
description: Retrieve or manage secrets using the secrets CLI. Use when accessing stored credentials, API keys, or other sensitive data.
allowed-tools: Bash(secrets *)
---

# Secrets Management

Use the `secrets` CLI to access credentials securely.

## Commands

| Command | Description |
|---------|-------------|
| `secrets get <name>` | Retrieve secret value (copies to clipboard) |
| `secrets get <name> --print` | Print value to stdout (for scripts) |
| `secrets get <name> --network` | Force fetch from GCP Secret Manager |
| `secrets get <name> --raw` | Return raw JSON with secrets-library metadata instead of the unwrapped value |
| `secrets get <name> --read-through` | Check local first, fall back to network |
| `secrets store <name> <value>` | Store a secret locally |
| `secrets store <name> <value> --network` | Store in GCP Secret Manager |
| `secrets list` | List local secrets |
| `secrets list --all` | List from both local and network |

## Common Secrets

- `hestia-hass-api-access` - Home Assistant API token
- `ntfy-basic-auth-password` - ntfy.sh authentication
- `EXA_API_KEY` - Exa search API

## Usage with HTTPie

```bash
http -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/states
```

## Important

- Use `--print` for scripts (default copies to clipboard)
- Do NOT use `--raw` when you want the secret value — `--raw` returns the secrets-library JSON envelope, not the unwrapped value
- Use `--ignore-stdin` with HTTPie to avoid hangs
- Never log or print secret values directly
- Handle missing secrets gracefully

## Task

$ARGUMENTS
