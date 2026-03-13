package main

func formatEntry(e LogEntry) string {
	s := e.Timestamp + " "
	if e.PID != "" {
		s += "[" + e.PID + "] "
	}
	s += e.Level + " "
	if e.Component != "" {
		s += e.Component
		if e.Window != "" {
			s += "(@" + e.Window + ")"
		}
		s += ": "
	}
	s += e.Message
	return s
}
