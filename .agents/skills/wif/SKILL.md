---
name: wif
description: Add Workload Identity Federation (WIF) authentication for GCP services on non-GCE machines. Use when setting up keyless GCP auth.
---

# Workload Identity Federation (WIF)

Keyless GCP authentication for machines outside GCE, using self-issued JWTs and service account impersonation.

## Architecture

```
EC P-256 key (SOPS secret)
  → gcp-wif-token signs JWT
    → GCP STS exchanges JWT for federated token
      → Federated token impersonates service account
```

## Adding WIF to a New Machine

### 1. Generate an EC P-256 key pair

```bash
openssl ecparam -name prime256v1 -genkey -noout -out /tmp/ec-key.pem
openssl ec -in /tmp/ec-key.pem -pubout -out /tmp/ec-pub.pem
```

### 2. Store the private key in SOPS

```bash
just sops-edit --set "$(printf '[\"gcp-identity-key\"] \"%s\"' "$(cat /tmp/ec-key.pem)")" systems/<machine>/secrets.yaml
```

Ensure `.sops.yaml` has a creation rule for the machine.

### 3. Extract public key coordinates for infrastructure

```bash
openssl ec -pubin -in /tmp/ec-pub.pem -text -noout 2>/dev/null
```

Extract the base64url-encoded x and y coordinates and add them to `infra/tofu.tfvars` under `wif_machine_keys`:

```hcl
wif_machine_keys = {
  hestia = { x = "...", y = "..." }
  <machine> = { x = "...", y = "..." }
}
```

### 4. Add WIF IAM binding in infrastructure

Create or update the machine's infra module (e.g. `infra/modules/<machine>/main.tofu`):

```hcl
resource "google_service_account_iam_member" "<machine>_wif" {
  service_account_id = google_service_account.<sa>.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${var.workload_identity_pool}/subject/<machine>"
}
```

The `workload_identity_pool` comes from `module.workload_identity.pool_name` in the root module.

### 5. Deploy infrastructure

```bash
bin/deploy-infra
```

### 6. Configure the NixOS service

Set three environment variables on the systemd service:

```nix
Environment = [
  "GOOGLE_APPLICATION_CREDENTIALS=${credentialConfig}"
  "GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES=1"
  "GOOGLE_CLOUD_PROJECT=${gcpProjectId}"
];
```

The credential config JSON uses the executable credential source pattern:

```nix
credentialConfig = pkgs.writeText "gcp-credential-config.json" (
  builtins.toJSON {
    type = "external_account";
    audience = wifAudience;
    subject_token_type = "urn:ietf:params:oauth:token-type:jwt";
    token_url = "https://sts.googleapis.com/v1/token";
    credential_source.executable = {
      command = "${gcp-wif-token}/bin/gcp-wif-token /run/secrets/gcp-identity-key.pem ${wifIssuerUrl} ${wifSubject} ${wifAudience}";
      timeout_millis = 5000;
    };
    service_account_impersonation_url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${saEmail}:generateAccessToken";
  }
);
```

## Gotchas

- **`GOOGLE_EXTERNAL_ACCOUNT_ALLOW_EXECUTABLES=1`** — GCP client libraries silently reject executable credential sources without this. No error, just fails to authenticate.
- **`GOOGLE_CLOUD_PROJECT`** — External accounts cannot auto-detect the project ID (unlike default GCE credentials). Omitting this causes "project not found" errors from GCS/PubSub clients.

## Key Files

| Path | Purpose |
|------|---------|
| `infra/modules/workload-identity/` | WIF pool, provider, OIDC bucket |
| `infra/modules/hestia/main.tofu` | Hestia SA + WIF IAM binding |
| `nix/nixpkgs/gcp-wif-token/` | JWT signing tool |
| `systems/hestia/run/services/hass-backup/default.nix` | Working example |

## Task

$ARGUMENTS
