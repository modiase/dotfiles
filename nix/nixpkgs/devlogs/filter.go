package main

import "strings"

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
