---
name: hekate
description: Work with hekate, the locked-down VPN gateway (Raspberry Pi 4). Use when modifying hekate configuration.
---

# Hekate (Locked-Down VPN Gateway)

Hekate is a Raspberry Pi 4 configured as a hardened WireGuard VPN gateway with minimal attack surface.

## What You CANNOT Do

- **Cannot SSH interactively** - `ForceCommand` restricts all SSH sessions to dashboard TUI only
- **Cannot deploy remotely** - `bin/activate deploy hekate` will NOT work
- **Cannot inspect system state** - No shell access means no `journalctl`, `systemctl status`, etc.
- **Cannot run arbitrary commands** - System is intentionally locked down

## How to Deploy

1. Build the SD card image: `build-image hekate`
2. Flash to SD card (or use `-d /dev/diskX`)
3. Insert SD card into hekate and boot

## Debugging Approach

Since you cannot inspect hekate directly:
- **Reason from configuration** - Trace through Nix modules to understand behaviour
- **Test locally**: `nix-instantiate --eval` or `nix eval` to check configuration
- **Ask the user** - They may have physical access
- **Never suggest SSH commands** - They will not work

## Key Architecture

- **sops-nix** for secrets with age key derived from device serial number
- **Age key** generated during NixOS activation (not systemd) to `/etc/age/key.txt`
- **WireGuard private key** decrypted by sops-nix during activation
- **Dashboard** accessible via SSH with ForceCommand (TUI only)

## Task

$ARGUMENTS
