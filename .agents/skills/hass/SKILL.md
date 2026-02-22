---
name: hass
description: Work with Home Assistant on hestia (Raspberry Pi 4). Use when working with Home Assistant or hestia system.
---

# Home Assistant (Hestia)

Hestia is a Raspberry Pi 4 running Home Assistant with multi-protocol IoT support.

## Services

| Service | Port | Path | Notes |
|---------|------|------|-------|
| Home Assistant | 8123 | `/hass/` | Core automation |
| Zigbee2MQTT | 8080 | `/zigbee/` | SONOFF Dongle Plus |
| Mosquitto | 1883 | - | MQTT broker (localhost) |
| Matter Server | - | - | Matter protocol |
| OTBR | 8081 | - | Thread/OpenThread Border Router |
| TK700 Dashboard | 3000 | `/projector/` | BenQ projector control |

## API Access

```bash
# Get token
secrets get hestia-hass-api-access --print

# Single request
http -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/states

# Create session (token cached)
http --session=hestia -A bearer -a "$(secrets get hestia-hass-api-access --print)" \
  GET http://hestia.local/hass/api/

# Reuse session
http --session=hestia GET http://hestia.local/hass/api/states

# Reset stale token
rm -rf ~/.config/httpie/sessions/hestia.local
```

Use `--ignore-stdin` with HTTPie when not piping data to avoid hangs.

## Deployment

Hestia has `manageRemotely = true`, so both methods work:

```bash
# Live NixOS rebuild (running system)
bin/activate deploy hestia

# Fresh SD card image
build-image hestia

# Build and flash
build-image hestia -d /dev/diskX
```

## Backup/Restore

- **Schedule**: Daily at 03:00 UTC
- **Destination**: GCS `modiase-backups/hestia/snapshots/`
- **Auth**: Workload Identity Federation (WIF) via `gcp-identity-key` — see `wif` skill
- **Encryption**: Age encryption with runtime-derived key

```bash
# Manual restore
hass-restore --list                           # List snapshots
hass-restore --from-latest                    # Restore newest
hass-restore --from-snapshot 2025-01-27T12:00:00Z
```

Auto-restore runs on fresh install (checks for `.backup-restored` marker).

## Debugging

```bash
# Check logs
journalctl -u home-assistant
journalctl -u hass-backup

# Backup status
cat /var/lib/hass/.backup-status.json
```

## Key Files

- Config: `/etc/home-assistant/configuration.nix`
- State: `/var/lib/hass/`
- Custom component: `benq_tk700` (projector control)

## Task

$ARGUMENTS
