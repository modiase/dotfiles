package main

import (
	"bufio"
	"os/exec"
	"runtime"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

type LogEntry struct {
	Timestamp string
	Level     string
	Component string
	Instance  string
	Window    string
	PID       string
	Message   string
}

func extractTimestamp(s string) string {
	if len(s) < 19 || s[4] != '-' {
		return s
	}
	// macOS compact: "2026-03-13 06:05:38.190 Db  logger[PID:TID]"
	if s[10] == ' ' && s[13] == ':' {
		return s[:23]
	}
	// journalctl short-iso: "2026-03-13T06:05:38+0000 hostname logger[PID]:"
	if s[10] == 'T' && s[13] == ':' {
		spaceIdx := strings.Index(s, " ")
		if spaceIdx > 0 {
			return s[:spaceIdx]
		}
	}
	return s
}

// extractPID finds PID from log prefix: macOS "process[PID:TID]" or journalctl "process[PID]"
func extractPID(prefix string) string {
	bracketIdx := strings.LastIndex(prefix, "[")
	if bracketIdx < 0 {
		return ""
	}
	rest := prefix[bracketIdx+1:]
	if endIdx := strings.IndexAny(rest, ":]"); endIdx > 0 {
		return rest[:endIdx]
	}
	return ""
}

// extractInstance splits "component{instance}" into component and instance.
func extractInstance(comp string) (string, string) {
	if i := strings.LastIndex(comp, "{"); i >= 0 {
		if strings.HasSuffix(comp, "}") {
			return comp[:i], comp[i+1 : len(comp)-1]
		}
	}
	return comp, ""
}

func parseLogEntry(line string) LogEntry {
	entry := LogEntry{}

	idx := strings.Index(line, "[devlogs] ")
	if idx < 0 {
		entry.Message = line
		return entry
	}

	prefix := strings.TrimSpace(line[:idx])
	entry.Timestamp = extractTimestamp(prefix)
	entry.PID = extractPID(prefix)
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
		comp, entry.Instance = extractInstance(comp)
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

func fetchHistory(duration string) tea.Cmd {
	return func() tea.Msg {
		cmd := buildHistoryCmd(duration)
		out, err := cmd.Output()
		if err != nil {
			return historyEntriesMsg(nil)
		}
		var entries []LogEntry
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			if line == "" || !strings.Contains(line, "[devlogs]") {
				continue
			}
			entries = append(entries, parseLogEntry(line))
		}
		return historyEntriesMsg(entries)
	}
}

func streamLogs(history string, live bool, ch chan<- LogEntry) {
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

	if !live {
		return
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
