---
name: hermes
description: Work with hermes, the GCE VM hosting web services. Use when modifying hermes configuration.
---

# Hermes (GCE VM)

Hermes is a GCE VM (e2-micro, europe-west2) running multiple web services.

## Services

| Service | Port | Purpose |
|---------|------|---------|
| Nginx | 80, 443 | Reverse proxy, TLS termination (Cloudflare Origin SSL) |
| Authelia | 9091 | Authentication/authorization |
| ntfy.sh | 8080 | Push notifications (GCS-backed) |
| MongoDB | 27017 | Database (localhost only) |
| Redis | 6379 | Session storage for Authelia |
| fail2ban | - | Intrusion prevention |
| CVE Scanner | - | Security scanning (6-hourly watchlist, weekly packages) |

## Deployment

**Do NOT use `bin/activate deploy hermes`** - hermes doesn't have `manageRemotely = true`.

```bash
# Build and upload image to GCS
build-image hermes

# Build, upload, and deploy via Terraform (recreates instance)
build-image hermes deploy

# Redeploy existing image without rebuilding
build-image hermes deploy --no-build
```

## GCP Secrets Pattern

Secrets are fetched via gcloud and are JSON-wrapped:

```nix
gcloud = "${pkgs.google-cloud-sdk}/bin/gcloud";
getSecret = name:
  "${gcloud} secrets versions access latest --secret=${name} --project=modiase-infra | jq -r '.value'";
```

## Key Gotchas

- **Behind Cloudflare** - Real IP from `CF-Connecting-IP` header
- **Hardened SSH** - ChaCha20-Poly1305, MaxAuthTries=3, PermitRootLogin=prohibit-password
- **No root sudo** - `security.sudo.enable = false`
- **SSL key from Secret Manager** - Fetched at startup by `fetch-ssl-key` service

## Task

$ARGUMENTS
