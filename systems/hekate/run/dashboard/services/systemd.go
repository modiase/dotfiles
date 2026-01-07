package services

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// GetServiceStatus returns whether a service is active and its uptime
func GetServiceStatus(serviceName string) (bool, string, error) {
	// Check if service is active
	cmd := exec.Command("systemctl", "is-active", serviceName)
	output, err := cmd.Output()
	active := err == nil && strings.TrimSpace(string(output)) == "active"

	if !active {
		return false, "inactive", nil
	}

	// Get uptime using systemctl show
	cmd = exec.Command("systemctl", "show", serviceName, "--property=ActiveEnterTimestamp", "--value")
	output, err = cmd.Output()
	if err != nil {
		return true, "unknown", nil
	}

	timestamp := strings.TrimSpace(string(output))
	if timestamp == "" {
		return true, "unknown", nil
	}

	// Parse timestamp and calculate uptime
	// Format: "Day YYYY-MM-DD HH:MM:SS TZ"
	layout := "Mon 2006-01-02 15:04:05 MST"
	t, err := time.Parse(layout, timestamp)
	if err != nil {
		// Try without day name
		layout = "2006-01-02 15:04:05 MST"
		t, err = time.Parse(layout, timestamp)
		if err != nil {
			return true, "unknown", nil
		}
	}

	uptime := time.Since(t)
	uptimeStr := formatDuration(uptime)

	return true, uptimeStr, nil
}

func formatDuration(d time.Duration) string {
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh %dm", days, hours, minutes)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
