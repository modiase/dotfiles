package main

import "strings"

var levelSeverity = map[string]int{
	"DEBUG":   0,
	"INFO":    1,
	"WARN":    2,
	"WARNING": 2,
	"ERROR":   3,
}

func matchLevel(minLevel string, entry LogEntry) bool {
	if minLevel == "" {
		return true
	}
	min, ok := levelSeverity[strings.ToUpper(minLevel)]
	if !ok {
		return true
	}
	sev, ok := levelSeverity[strings.ToUpper(entry.Level)]
	if !ok {
		return true
	}
	return sev >= min
}

func matchFilter(filter string, line string) bool {
	if filter == "" {
		return true
	}
	lower := strings.ToLower(line)
	for _, token := range strings.Fields(strings.ToLower(filter)) {
		if !strings.Contains(lower, token) {
			return false
		}
	}
	return true
}
