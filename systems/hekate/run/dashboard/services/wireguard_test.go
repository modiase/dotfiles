package services

import (
	"strings"
	"testing"
	"time"
)

func TestParseWireGuardDump(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantErr   bool
		errMsg    string
		checkFunc func(*testing.T, *WireGuardInfo)
	}{
		{
			name: "valid dump with active peers",
			input: "REDACTED\trndgZCWa1234567890ABCDEF+2AE=\t51820\toff\n" +
				"Od72AK2AKZptCZcGJ+PvF78/9EwlFonpWP8X/fCzLGE=\t(none)\t192.168.1.100:51820\t10.0.0.2/32\t1704067200\t123456789\t987654321\t21\n" +
				"/tdJioXk+bkkn0HIATk9t5nMNZMTVqHc3KJA5+vm+w8=\t(none)\t(none)\t10.0.0.3/32\t0\t0\t0\t21\n",
			wantErr: false,
			checkFunc: func(t *testing.T, info *WireGuardInfo) {
				if info.Interface.Name != "wg0" {
					t.Errorf("Interface.Name = %q, want %q", info.Interface.Name, "wg0")
				}
				if info.Interface.PublicKey != "rndgZCWa1234567890ABCDEF+2AE=" {
					t.Errorf("Interface.PublicKey = %q, want %q", info.Interface.PublicKey, "rndgZCWa1234567890ABCDEF+2AE=")
				}
				if info.Interface.ListenPort != 51820 {
					t.Errorf("Interface.ListenPort = %d, want %d", info.Interface.ListenPort, 51820)
				}
				if len(info.Peers) != 2 {
					t.Fatalf("len(Peers) = %d, want %d", len(info.Peers), 2)
				}

				peer1 := info.Peers[0]
				if peer1.PublicKey != "Od72AK2AKZptCZcGJ+PvF78/9EwlFonpWP8X/fCzLGE=" {
					t.Errorf("Peer[0].PublicKey = %q", peer1.PublicKey)
				}
				if peer1.Endpoint != "192.168.1.100:51820" {
					t.Errorf("Peer[0].Endpoint = %q, want %q", peer1.Endpoint, "192.168.1.100:51820")
				}
				if peer1.AllowedIPs != "10.0.0.2/32" {
					t.Errorf("Peer[0].AllowedIPs = %q", peer1.AllowedIPs)
				}
				expectedTime := time.Unix(1704067200, 0)
				if !peer1.LatestHandshake.Equal(expectedTime) {
					t.Errorf("Peer[0].LatestHandshake = %v, want %v", peer1.LatestHandshake, expectedTime)
				}
				if peer1.TransferRx != 123456789 {
					t.Errorf("Peer[0].TransferRx = %d, want %d", peer1.TransferRx, 123456789)
				}
				if peer1.TransferTx != 987654321 {
					t.Errorf("Peer[0].TransferTx = %d, want %d", peer1.TransferTx, 987654321)
				}
				if peer1.PersistentKeepalive != 21 {
					t.Errorf("Peer[0].PersistentKeepalive = %d, want %d", peer1.PersistentKeepalive, 21)
				}

				peer2 := info.Peers[1]
				if peer2.Endpoint != "(none)" {
					t.Errorf("Peer[1].Endpoint = %q, want %q", peer2.Endpoint, "(none)")
				}
				if !peer2.LatestHandshake.IsZero() {
					t.Errorf("Peer[1].LatestHandshake should be zero time")
				}
			},
		},
		{
			name:    "interface with listen port off",
			input:   "REDACTED\tpUBLICKEY=\toff\toff\n",
			wantErr: false,
			checkFunc: func(t *testing.T, info *WireGuardInfo) {
				if info.Interface.ListenPort != 0 {
					t.Errorf("Interface.ListenPort = %d, want %d", info.Interface.ListenPort, 0)
				}
			},
		},
		{
			name:    "interface with listen port (none)",
			input:   "REDACTED\tpUBLICKEY=\t(none)\toff\n",
			wantErr: false,
			checkFunc: func(t *testing.T, info *WireGuardInfo) {
				if info.Interface.ListenPort != 0 {
					t.Errorf("Interface.ListenPort = %d, want %d", info.Interface.ListenPort, 0)
				}
			},
		},
		{
			name: "peer with keepalive off",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\t10.0.0.2/32\t0\t0\t0\toff\n",
			wantErr: false,
			checkFunc: func(t *testing.T, info *WireGuardInfo) {
				if len(info.Peers) != 1 {
					t.Fatalf("len(Peers) = %d, want %d", len(info.Peers), 1)
				}
				if info.Peers[0].PersistentKeepalive != 0 {
					t.Errorf("Peer[0].PersistentKeepalive = %d, want %d", info.Peers[0].PersistentKeepalive, 0)
				}
			},
		},
		{
			name:    "empty response",
			input:   "",
			wantErr: true,
			errMsg:  "empty response",
		},
		{
			name:    "ERROR prefix",
			input:   "ERROR: WireGuard interface not available",
			wantErr: true,
			errMsg:  "WireGuard error: WireGuard interface not available",
		},
		{
			name:    "interface line too few fields",
			input:   "REDACTED\tpUBKEY\n",
			wantErr: true,
			errMsg:  "expected at least 4 fields",
		},
		{
			name: "peer line too few fields",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\n",
			wantErr: true,
			errMsg:  "expected at least 8 fields",
		},
		{
			name:    "invalid listen port",
			input:   "REDACTED\tpUBLICKEY=\tinvalid\toff\n",
			wantErr: true,
			errMsg:  "failed to parse listen port",
		},
		{
			name: "invalid handshake timestamp",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\t10.0.0.2/32\tinvalid\t0\t0\t21\n",
			wantErr: true,
			errMsg:  "failed to parse handshake timestamp",
		},
		{
			name: "invalid transfer rx",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\t10.0.0.2/32\t0\tinvalid\t0\t21\n",
			wantErr: true,
			errMsg:  "failed to parse RX bytes",
		},
		{
			name: "invalid transfer tx",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\t10.0.0.2/32\t0\t0\tinvalid\t21\n",
			wantErr: true,
			errMsg:  "failed to parse TX bytes",
		},
		{
			name: "invalid keepalive",
			input: "REDACTED\tpUBLICKEY=\t51820\toff\n" +
				"peerPUBKEY=\t(none)\t(none)\t10.0.0.2/32\t0\t0\t0\tinvalid\n",
			wantErr: true,
			errMsg:  "failed to parse keepalive",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			info, err := parseWireGuardDump(tt.input)

			if tt.wantErr {
				if err == nil {
					t.Errorf("parseWireGuardDump() expected error containing %q, got nil", tt.errMsg)
					return
				}
				if !strings.Contains(err.Error(), tt.errMsg) {
					t.Errorf("parseWireGuardDump() error = %q, want error containing %q", err.Error(), tt.errMsg)
				}
				return
			}

			if err != nil {
				t.Fatalf("parseWireGuardDump() unexpected error: %v", err)
			}

			if tt.checkFunc != nil {
				tt.checkFunc(t, info)
			}
		})
	}
}
