# Dotfiles & Infrastructure

## Quickstart

```bash
git clone git@github.com:modiase/Dotfiles.git ~/Dotfiles \
    && cd ~/Dotfiles \
    && bin/bootstrap \
    && source ~/.nix-profile/etc/profile.d/nix.sh \
    && bin/activate
```

## Building System Images

```bash
nix run .#build-system-image            # Interactive selection
nix run .#build-system-image -- hekate  # Build specific system
```

## Secrets Management

The `secrets` CLI provides unified access to credentials across platforms (macOS Keychain, Linux pass, GCP Secret Manager).

```bash
secrets list                              # List local secrets
secrets list --network                    # List GCP secrets
secrets get <name>                        # Get secret (copies to clipboard)
secrets get <name> --read-through         # Try local first, fall back to GCP
secrets get <name> --read-through --store-local  # Cache GCP secret locally
secrets store <name> <value>              # Store a secret
```

### GCP Authentication

The `--network` flag uses Google Cloud Secret Manager, which requires Application Default Credentials (ADC).

**macOS / Interactive:**
```bash
gcloud auth application-default login
```

**Headless servers:**
```bash
gcloud auth application-default login --no-browser
```
This outputs a URL to visit on another machine. Complete authentication there and paste the code back.

**Verify ADC is configured:**
```bash
gcloud auth application-default print-access-token
```

