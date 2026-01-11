package services

import (
	"io"
	"net"
	"time"
)

const dnsLogsSocket = "/run/dns-logs/logs.sock"

func GetDNSLogs() (string, error) {
	if IsDemoMode() {
		return GetDemoDNSLogs(), nil
	}

	conn, err := net.DialTimeout("unix", dnsLogsSocket, 5*time.Second)
	if err != nil {
		return "DNS logs unavailable: " + err.Error(), nil
	}
	defer conn.Close()

	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	output, err := io.ReadAll(conn)
	if err != nil {
		return "DNS logs unavailable: " + err.Error(), nil
	}
	if len(output) == 0 {
		return "No DNS logs found", nil
	}
	return string(output), nil
}
