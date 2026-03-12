package main

import (
	"bufio"
	"os/exec"
	"runtime"
	"strings"
)

type LogEntry struct {
	Timestamp string
	Level     string
	Component string
	Window    string
	Message   string
	Raw       string
}

func parseLogEntry(line string) LogEntry {
	entry := LogEntry{Raw: line}

	idx := strings.Index(line, "[devlogs] ")
	if idx < 0 {
		entry.Message = line
		return entry
	}

	entry.Timestamp = strings.TrimSpace(line[:idx])
	rest := line[idx+len("[devlogs] "):]

	parts := strings.SplitN(rest, " ", 2)
	if len(parts) < 2 {
		entry.Message = rest
		return entry
	}
	entry.Level = parts[0]
	rest = parts[1]

	colonIdx := strings.Index(rest, ": ")
	if colonIdx >= 0 {
		comp := rest[:colonIdx]
		if strings.HasSuffix(comp, ")") {
			if i := strings.LastIndex(comp, "(@"); i >= 0 {
				entry.Window = comp[i+2 : len(comp)-1]
				comp = comp[:i]
			}
		}
		entry.Component = comp
		entry.Message = rest[colonIdx+2:]
	} else {
		entry.Message = rest
	}

	return entry
}

func buildStreamCmd() *exec.Cmd {
	if runtime.GOOS == "darwin" {
		return exec.Command("log", "stream",
			"--predicate", `eventMessage BEGINSWITH "[devlogs]"`,
			"--info", "--debug", "--style", "compact")
	}
	return exec.Command("journalctl", "-t", "devlogs", "-f", "--no-pager", "-o", "short-iso")
}

func buildHistoryCmd(duration string) *exec.Cmd {
	if runtime.GOOS == "darwin" {
		return exec.Command("log", "show",
			"--predicate", `eventMessage BEGINSWITH "[devlogs]"`,
			"--last", duration,
			"--info", "--debug", "--style", "compact")
	}
	return exec.Command("journalctl", "-t", "devlogs",
		"--since", duration+" ago", "--no-pager", "-o", "short-iso")
}

type logLineMsg LogEntry

func streamLogs(history string, ch chan<- LogEntry) {
	defer close(ch)
	if history != "" {
		cmd := buildHistoryCmd(history)
		out, err := cmd.Output()
		if err == nil {
			for _, line := range strings.Split(string(out), "\n") {
				line = strings.TrimSpace(line)
				if line == "" || !strings.Contains(line, "[devlogs]") {
					continue
				}
				ch <- parseLogEntry(line)
			}
		}
	}

	cmd := buildStreamCmd()
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return
	}
	if err := cmd.Start(); err != nil {
		return
	}

	scanner := bufio.NewScanner(stdout)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.Contains(line, "[devlogs]") {
			continue
		}
		ch <- parseLogEntry(line)
	}
}
