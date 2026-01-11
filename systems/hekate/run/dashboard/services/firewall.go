package services

import (
	"io"
	"net"
	"time"
)

const firewallLogsSocket = "/run/firewall-logs/logs.sock"

func GetFirewallLogs() (string, error) {
	if IsDemoMode() {
		return GetDemoFirewallLogs(), nil
	}

	conn, err := net.DialTimeout("unix", firewallLogsSocket, 5*time.Second)
	if err != nil {
		return "Firewall logs unavailable: " + err.Error(), nil
	}
	defer conn.Close()

	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	output, err := io.ReadAll(conn)
	if err != nil {
		return "Firewall logs unavailable: " + err.Error(), nil
	}
	if len(output) == 0 {
		return "No blocked connections logged", nil
	}
	return string(output), nil
}
