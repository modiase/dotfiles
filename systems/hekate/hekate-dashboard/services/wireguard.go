package services

import (
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"time"
)

type WireGuardPeer struct {
	PublicKey           string
	Endpoint            string
	AllowedIPs          string
	LatestHandshake     time.Time
	TransferRx          uint64
	TransferTx          uint64
	PersistentKeepalive int
}

type WireGuardInterface struct {
	Name       string
	PublicKey  string
	ListenPort int
}

type WireGuardInfo struct {
	Interface WireGuardInterface
	Peers     []WireGuardPeer
	Timestamp time.Time
}

func parseWireGuardDump(output string) (*WireGuardInfo, error) {
	if strings.HasPrefix(output, "ERROR:") {
		return nil, fmt.Errorf("WireGuard error: %s", strings.TrimPrefix(output, "ERROR: "))
	}

	output = strings.TrimSpace(output)
	if output == "" {
		return nil, fmt.Errorf("empty response from WireGuard server")
	}

	lines := strings.Split(output, "\n")

	interfaceLine := strings.Split(lines[0], "\t")
	if len(interfaceLine) < 4 {
		return nil, fmt.Errorf("invalid interface line format: expected at least 4 fields, got %d", len(interfaceLine))
	}

	var listenPort int
	if interfaceLine[2] != "off" && interfaceLine[2] != "(none)" {
		var err error
		listenPort, err = strconv.Atoi(interfaceLine[2])
		if err != nil {
			return nil, fmt.Errorf("failed to parse listen port %q: %w", interfaceLine[2], err)
		}
	}

	info := &WireGuardInfo{
		Interface: WireGuardInterface{
			Name:       "wg0",
			PublicKey:  interfaceLine[1],
			ListenPort: listenPort,
		},
		Peers:     make([]WireGuardPeer, 0),
		Timestamp: time.Now(),
	}

	for i, line := range lines[1:] {
		if line == "" {
			continue
		}

		fields := strings.Split(line, "\t")
		if len(fields) < 8 {
			return nil, fmt.Errorf("invalid peer line %d: expected at least 8 fields, got %d", i+1, len(fields))
		}

		var latestHandshake time.Time
		handshakeUnix, err := strconv.ParseInt(fields[4], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("failed to parse handshake timestamp for peer %d (%q): %w", i+1, fields[4], err)
		}
		if handshakeUnix > 0 {
			latestHandshake = time.Unix(handshakeUnix, 0)
		}

		transferRx, err := strconv.ParseUint(fields[5], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("failed to parse RX bytes for peer %d (%q): %w", i+1, fields[5], err)
		}

		transferTx, err := strconv.ParseUint(fields[6], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("failed to parse TX bytes for peer %d (%q): %w", i+1, fields[6], err)
		}

		var keepalive int
		if fields[7] != "off" && fields[7] != "(none)" {
			var err error
			keepalive, err = strconv.Atoi(fields[7])
			if err != nil {
				return nil, fmt.Errorf("failed to parse keepalive for peer %d (%q): %w", i+1, fields[7], err)
			}
		}

		info.Peers = append(info.Peers, WireGuardPeer{
			PublicKey:           fields[0],
			Endpoint:            fields[2],
			AllowedIPs:          fields[3],
			LatestHandshake:     latestHandshake,
			TransferRx:          transferRx,
			TransferTx:          transferTx,
			PersistentKeepalive: keepalive,
		})
	}

	return info, nil
}

func GetWireGuardInfo() (*WireGuardInfo, error) {
	conn, err := net.Dial("unix", "/run/wg-status/status.sock")
	if err != nil {
		return nil, fmt.Errorf("failed to connect to WireGuard status server: %w", err)
	}
	defer conn.Close()

	if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return nil, fmt.Errorf("failed to set read deadline: %w", err)
	}

	data, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("failed to read WireGuard status: %w", err)
	}

	return parseWireGuardDump(string(data))
}
