package services

import (
	"fmt"
	"os/exec"
	"strings"
	"time"
)

func GetSystemTimeInfo() (string, error) {
	cmd := exec.Command("timedatectl", "status")
	output, err := cmd.Output()
	if err != nil {
		return "Time sync status unavailable\n\nNote: timedatectl requires systemd and appropriate permissions", nil
	}

	lines := strings.Split(string(output), "\n")
	var relevant []string

	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		if strings.Contains(line, "Local time:") ||
			strings.Contains(line, "Universal time:") ||
			strings.Contains(line, "Time zone:") {
			relevant = append(relevant, line)
		}
	}

	if len(relevant) == 0 {
		return string(output), nil
	}

	return strings.Join(relevant, "\n"), nil
}

func SetSystemTime(newTime time.Time) error {
	return fmt.Errorf("time setting is not supported on this system")
}
