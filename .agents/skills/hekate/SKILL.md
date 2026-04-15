---
name: hekate
description: Work with hekate, the locked-down VPN gateway (Raspberry Pi 4). Use when modifying hekate configuration, nginx routing, dashboard, or any hekate service.
---

# Hekate (Locked-Down VPN Gateway)

Hekate is a Raspberry Pi 4 configured as a hardened WireGuard VPN gateway with minimal attack surface.

## Network Addresses

Hekate is reachable on multiple addresses — any change to nginx routing must work on **all** of them:

| Address       | Network             | Protocol                         |
| ------------- | ------------------- | -------------------------------- |
| 192.168.1.110 | LAN                 | HTTP (port 80)                   |
| 10.0.100.110  | WireGuard           | HTTP (port 80)                   |
| hekate.home   | DNS (pdns-recursor) | HTTPS (port 443) + HTTP redirect |
| hekate.local  | mDNS (Avahi)        | HTTP (port 80)                   |
| h / h.home    | DNS alias           | HTTP (port 80)                   |

## What You CANNOT Do

- **Cannot SSH interactively** — `ForceCommand` restricts all SSH sessions to dashboard TUI only
- **Cannot deploy remotely** — `bin/activate deploy hekate` will NOT work
- **Cannot inspect system state** — no shell access means no `journalctl`, `systemctl status`, etc.
- **Never suggest SSH commands** — they will not work

## How to Deploy

1. Build the SD card image: `build-image hekate`
2. Flash to SD card (or use `-d /dev/diskX`)
3. Insert SD card into hekate and boot

## Debugging Approach

Since you cannot inspect hekate directly:

- **Reason from configuration** — trace through Nix modules to understand behaviour
- **Test locally**: `nix-instantiate --eval` or `nix eval` to check configuration
- **Ask the user** — they may have physical access

## Nginx Routing

Two vhosts, both defined declaratively via NixOS modules:

### `hekate.home` (HTTPS/443)

- ACME via step-ca, forceSSL
- `/` — dashboard SPA (Angular, base href `/`)
- `/dashboard` — dashboard SPA (Angular, base href `/dashboard/`)
- `/api/` — proxy to dashboard backend (port 8080)

### `h` (HTTP/80, default server)

- `default = true` — catches all HTTP requests regardless of hostname (raw IPs, mDNS, etc.)
- Server aliases: `h.home`
- `/` — h-links short URL redirector (proxy to port 8090)
- `/dashboard` — dashboard SPA (Angular, base href `/dashboard/`)
- `/api/` — proxy to dashboard backend (port 8080)

Locations for the `h` vhost are split across two modules:

- `run/services/h-links/service.nix` — defines `/` and listen directives
- `run/dashboard/service.nix` — defines `/dashboard`, `/api/`, and `default = true`

NixOS merges these declaratively.

## Services

### Dashboard (`run/dashboard/`)

- **Backend** (Go): port 8080, DynamicUser, reads from unix sockets in `/run/`
- **Web UI** (Angular SPA): static files served by nginx, calls `/api/` endpoints
- **TUI** (Go, Bubble Tea): SSH ForceCommand for admin user
- **API endpoints**: `/api/status`, `/api/health`, `/api/ssh`, `/api/wireguard`, `/api/dns`, `/api/firewall`, `/api/network`, `/api/time`, `/api/vpn/*`

### h-links (`run/services/h-links/`)

- Short URL redirector — `h/<name>` redirects to configured target
- Go service on port 8090
- Links defined in `links.json` (base) + `/var/lib/h-links/overrides.json` (runtime)

### Other services (`run/services/`)

- **step-ca** (`step-ca.nix`) — ACME certificate authority, port 8443
- **wg-status-server** (`wg-status-server.nix`) — WireGuard status via unix socket
- **dns-logs-server** (`dns-logs-server.nix`) — DNS query logs via unix socket
- **firewall-logs-server** (`firewall-logs-server.nix`) — firewall drop logs via unix socket
- **vpn-routing-server** (`vpn-routing-server.nix`) — VPN routing control daemon via unix socket
- **ssh-logger** (`ssh-logger.nix`) — streams sshd journal to `/var/log/ssh-access.log`

### System services (configured in `services.nix`)

- **pdns-recursor** — DNS resolver with local zone (`home.zone`)
- **Avahi** — mDNS service discovery
- **openssh** — SSH with ForceCommand to TUI

## Secrets

- **sops-nix** with age key derived from device serial number
- Age key generated during NixOS activation to `/etc/age/key.txt`
- WireGuard private key decrypted by sops-nix during activation

## Task

$ARGUMENTS
