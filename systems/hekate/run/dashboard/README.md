# Hekate Dashboard

A secure, read-only monitoring dashboard for the Hekate VPN gateway, built with Bubble Tea.

## Features

### Three Tabs:

1. **Status** - Real-time system service status
   - WireGuard, SSH, Avahi, systemd-networkd
   - Service uptime display
   - Auto-refreshes every 5 seconds

2. **SSH** - Scrollable SSH access logs
   - Reads `/var/log/ssh-access.log` and rotated archives
   - Auto-refreshes every 5 seconds
   - Scroll with arrow keys, jump to top/bottom with g/G

3. **WireGuard** - WireGuard configuration and live logs
   - Top panel: Public key, peers, endpoints (no private keys)
   - Bottom panel: Live journalctl streaming
   - Filter logs: All, Handshakes, Connections, Errors (press 'f' to cycle)
   - Auto-refreshes every 2 seconds

## Security

- **Read-only access** - No write capabilities anywhere
- **Runs as admin user** - Dashboard executes via SSH ForceCommand as unprivileged `admin` user
- **Socket-based IPC** - Reads system data from Unix sockets (no privilege escalation)
- **World-readable data sources** - SSH logs, health metrics, WireGuard status (non-sensitive data)
- **No shell escape** - Pure Go TUI, no command execution
- **No secrets** - WireGuard private keys never displayed

## Building

### On macOS (development):
```bash
cd systems/hekate/hekate-dashboard
go mod download
go build
```

### On NixOS (production):
```bash
# From dotfiles root
nix-build systems/hekate/hekate-dashboard

# Or build the full system
nixos-rebuild build --flake .#hekate
```

## Usage

When you SSH to hekate as the `admin` user, the dashboard launches automatically via ForceCommand.

```bash
ssh admin@hekate
```

### Keyboard Controls:

- **1-3 or ← →** - Switch tabs
- **↑ ↓** - Scroll logs (SSH/WireGuard tabs)
- **g / G** - Jump to top/bottom
- **f** - Cycle filter levels (WireGuard tab only)
- **q or Ctrl+C** - Quit

## Architecture

```
hekate-dashboard/
├── main.go              # Entry point, tab navigation
├── components/          # UI components (tabs)
│   ├── status.go       # System services
│   ├── ssh.go          # SSH logs viewer
│   └── wireguard.go    # WireGuard config + logs
├── services/            # System interaction layer
│   ├── systemd.go      # Service status queries
│   ├── logs.go         # Log file reading
│   └── wireguard.go    # WireGuard info + journalctl
└── ui/                  # Shared UI components (future)
```

## Dependencies

- `bubbletea` - TUI framework
- `bubbles` - Viewport component
- `lipgloss` - Terminal styling
- `go-systemd` - Journalctl access

## License

MIT
