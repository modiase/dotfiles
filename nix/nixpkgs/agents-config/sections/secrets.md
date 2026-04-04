---
priority: 5
---

## Secret Handling — MANDATORY

**CRITICAL: Agents must NEVER read, display, or transfer secret material (private keys, passwords, tokens, API keys, certificates) in plain text.**

This applies to local files, remote hosts, environment variables, and any other source. Violations include:

- `cat /run/secrets/...` or `Read` on a secret file without piping to a processing command
- Piping secret content through SSH to the local machine
- Displaying secret values in logs, output, or conversation

**Permitted operations** — an agent may access a secret ONLY when the content is:

1. **Piped directly to a command** that consumes it without exposing the raw value (e.g., `openssl ... -in key.pem -pubout`)
2. **Written to a file** on the same host where the secret resides (e.g., `cp`, `sops --set`)
3. **Reduced to a non-reversible summary** such as a hash, fingerprint, or public key extraction (e.g., `sha256sum`, `openssl ec -in key.pem -pubout -outform DER | base64`)

All processing of secrets MUST happen on the host where the secret lives. Never transfer secret material between hosts.
