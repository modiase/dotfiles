package services

import (
	"os/exec"
)

func GetDNSLogs() (string, error) {
	cmd := exec.Command("journalctl", "-u", "unbound", "-n", "100", "--no-pager", "-o", "short-iso")
	output, err := cmd.Output()
	if err != nil {
		return "DNS logs unavailable: " + err.Error(), nil
	}
	if len(output) == 0 {
		return "No DNS logs found", nil
	}
	return string(output), nil
}
