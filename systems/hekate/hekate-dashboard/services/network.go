package services

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

type InterfaceStats struct {
	Name      string
	RxBytes   uint64
	TxBytes   uint64
	RxPackets uint64
	TxPackets uint64
	RxErrors  uint64
	TxErrors  uint64
	RxDropped uint64
	TxDropped uint64
}

type InterfaceRates struct {
	Name       string
	RxRate     float64
	TxRate     float64
	RxPackRate float64
	TxPackRate float64
}

var (
	lastStats     map[string]InterfaceStats
	lastStatsTime time.Time
)

func init() {
	lastStats = make(map[string]InterfaceStats)
	lastStatsTime = time.Now()
}

func GetInterfaceStats(iface string) (*InterfaceStats, error) {
	basePath := fmt.Sprintf("/sys/class/net/%s/statistics", iface)

	stats := &InterfaceStats{Name: iface}

	var err error
	stats.RxBytes, err = readStat(basePath + "/rx_bytes")
	if err != nil {
		return nil, err
	}

	stats.TxBytes, err = readStat(basePath + "/tx_bytes")
	if err != nil {
		return nil, err
	}

	stats.RxPackets, err = readStat(basePath + "/rx_packets")
	if err != nil {
		return nil, err
	}

	stats.TxPackets, err = readStat(basePath + "/tx_packets")
	if err != nil {
		return nil, err
	}

	stats.RxErrors, err = readStat(basePath + "/rx_errors")
	if err != nil {
		return nil, err
	}

	stats.TxErrors, err = readStat(basePath + "/tx_errors")
	if err != nil {
		return nil, err
	}

	stats.RxDropped, err = readStat(basePath + "/rx_dropped")
	if err != nil {
		return nil, err
	}

	stats.TxDropped, err = readStat(basePath + "/tx_dropped")
	if err != nil {
		return nil, err
	}

	return stats, nil
}

func GetInterfaceRates(iface string) (*InterfaceRates, error) {
	currentStats, err := GetInterfaceStats(iface)
	if err != nil {
		return nil, err
	}

	now := time.Now()
	rates := &InterfaceRates{Name: iface}

	if lastStat, exists := lastStats[iface]; exists {
		elapsed := now.Sub(lastStatsTime).Seconds()
		if elapsed > 0 {
			rates.RxRate = float64(currentStats.RxBytes-lastStat.RxBytes) / elapsed
			rates.TxRate = float64(currentStats.TxBytes-lastStat.TxBytes) / elapsed
			rates.RxPackRate = float64(currentStats.RxPackets-lastStat.RxPackets) / elapsed
			rates.TxPackRate = float64(currentStats.TxPackets-lastStat.TxPackets) / elapsed
		}
	}

	lastStats[iface] = *currentStats
	lastStatsTime = now

	return rates, nil
}

func FormatBytes(bytes uint64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := uint64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(bytes)/float64(div), "KMGTPE"[exp])
}

func FormatRate(bytesPerSec float64) string {
	const unit = 1024
	if bytesPerSec < unit {
		return fmt.Sprintf("%.0f B/s", bytesPerSec)
	}
	div, exp := float64(unit), 0
	for n := bytesPerSec / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB/s", bytesPerSec/div, "KMGTPE"[exp])
}

func readStat(path string) (uint64, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, err
	}

	value, err := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	if err != nil {
		return 0, err
	}

	return value, nil
}
