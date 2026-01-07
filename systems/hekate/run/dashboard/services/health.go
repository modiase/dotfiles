package services

import (
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"time"
)

type CPUStats struct {
	UsagePercent int
}

type MemoryStats struct {
	TotalKB      uint64
	UsedKB       uint64
	AvailableKB  uint64
	UsagePercent int
}

type SystemStats struct {
	UptimeSeconds      int
	LoadAvg1Min        string
	LoadAvg5Min        string
	LoadAvg15Min       string
	TemperatureCelsius int
}

type HealthInfo struct {
	Timestamp time.Time
	CPU       CPUStats
	Memory    MemoryStats
	System    SystemStats
}

func GetHealthInfo() (*HealthInfo, error) {
	conn, err := net.Dial("unix", "/run/health-status/status.sock")
	if err != nil {
		return nil, fmt.Errorf("failed to connect to health status server: %w", err)
	}
	defer conn.Close()

	if err := conn.SetReadDeadline(time.Now().Add(5 * time.Second)); err != nil {
		return nil, fmt.Errorf("failed to set read deadline: %w", err)
	}

	data, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("failed to read health status: %w", err)
	}

	output := string(data)
	if strings.HasPrefix(output, "ERROR:") {
		return nil, fmt.Errorf("Health error: %s", strings.TrimPrefix(output, "ERROR: "))
	}

	health := &HealthInfo{
		Timestamp: time.Now(),
	}

	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("invalid health data format: line missing colon delimiter: %q", line)
		}

		key, value := parts[0], parts[1]

		var err error
		switch key {
		case "CPU_PERCENT":
			health.CPU.UsagePercent, err = strconv.Atoi(value)
			if err != nil {
				return nil, fmt.Errorf("failed to parse CPU_PERCENT value %q: %w", value, err)
			}
		case "MEM_TOTAL_KB":
			health.Memory.TotalKB, err = strconv.ParseUint(value, 10, 64)
			if err != nil {
				return nil, fmt.Errorf("failed to parse MEM_TOTAL_KB value %q: %w", value, err)
			}
		case "MEM_USED_KB":
			health.Memory.UsedKB, err = strconv.ParseUint(value, 10, 64)
			if err != nil {
				return nil, fmt.Errorf("failed to parse MEM_USED_KB value %q: %w", value, err)
			}
		case "MEM_AVAILABLE_KB":
			health.Memory.AvailableKB, err = strconv.ParseUint(value, 10, 64)
			if err != nil {
				return nil, fmt.Errorf("failed to parse MEM_AVAILABLE_KB value %q: %w", value, err)
			}
		case "MEM_PERCENT":
			health.Memory.UsagePercent, err = strconv.Atoi(value)
			if err != nil {
				return nil, fmt.Errorf("failed to parse MEM_PERCENT value %q: %w", value, err)
			}
		case "UPTIME_SECONDS":
			health.System.UptimeSeconds, err = strconv.Atoi(value)
			if err != nil {
				return nil, fmt.Errorf("failed to parse UPTIME_SECONDS value %q: %w", value, err)
			}
		case "LOAD_AVG_1MIN":
			health.System.LoadAvg1Min = value
		case "LOAD_AVG_5MIN":
			health.System.LoadAvg5Min = value
		case "LOAD_AVG_15MIN":
			health.System.LoadAvg15Min = value
		case "TEMP_CELSIUS":
			health.System.TemperatureCelsius, err = strconv.Atoi(value)
			if err != nil {
				return nil, fmt.Errorf("failed to parse TEMP_CELSIUS value %q: %w", value, err)
			}
		default:
			return nil, fmt.Errorf("unknown health metric key: %q", key)
		}
	}

	return health, nil
}
