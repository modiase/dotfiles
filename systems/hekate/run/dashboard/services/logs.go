package services

import (
	"compress/gzip"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var (
	sshLogsCache      string
	sshLogsLastUpdate time.Time
	sshLogsModTimes   map[string]time.Time
)

func init() {
	sshLogsModTimes = make(map[string]time.Time)
}

// GetSSHLogs reads the SSH access log and all rotated logs, returning them concatenated
func GetSSHLogs() (string, error) {
	logDir := "/var/log"
	baseName := "ssh-access.log"

	files, err := filepath.Glob(filepath.Join(logDir, baseName+"*"))
	if err != nil {
		return "Failed to access log directory: " + err.Error(), nil
	}

	if len(files) == 0 {
		return "No SSH logs found at " + filepath.Join(logDir, baseName+"*"), nil
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i] > files[j]
	})

	changed := false
	newModTimes := make(map[string]time.Time)

	for _, file := range files {
		info, err := os.Stat(file)
		if err != nil {
			continue
		}
		modTime := info.ModTime()
		newModTimes[file] = modTime

		if oldModTime, exists := sshLogsModTimes[file]; !exists || !modTime.Equal(oldModTime) {
			changed = true
		}
	}

	if len(newModTimes) != len(sshLogsModTimes) {
		changed = true
	}

	if !changed && sshLogsCache != "" {
		return sshLogsCache, nil
	}

	sshLogsModTimes = newModTimes

	var allLogs strings.Builder

	for _, file := range files {
		content, err := readLogFile(file)
		if err != nil {
			continue
		}
		allLogs.WriteString(content)
		if !strings.HasSuffix(content, "\n") {
			allLogs.WriteString("\n")
		}
	}

	result := allLogs.String()
	if result == "" {
		return "No log content available", nil
	}

	sshLogsCache = result
	sshLogsLastUpdate = time.Now()

	return result, nil
}

func readLogFile(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()

	var reader io.Reader = file

	// Check if file is gzipped
	if strings.HasSuffix(path, ".gz") {
		gzReader, err := gzip.NewReader(file)
		if err != nil {
			return "", err
		}
		defer gzReader.Close()
		reader = gzReader
	}

	content, err := io.ReadAll(reader)
	if err != nil {
		return "", err
	}

	return string(content), nil
}
