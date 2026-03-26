package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
	flag "github.com/spf13/pflag"
)

func resolveWindowFilter(w string) string {
	if w == "-1" {
		return ""
	}
	if w != "" {
		return w
	}
	pane := os.Getenv("TMUX_PANE")
	if pane == "" {
		return ""
	}
	out, err := exec.Command("tmux", "display-message", "-t", pane, "-p", "#{window_index}").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func main() {
	// keep-sorted start
	history := flag.StringP("history", "H", "", "Show history (e.g. 1h, 30m, 2d)")
	level := flag.StringP("level", "l", "info", "Minimum log level (debug, info, warn, error)")
	noFollow := flag.BoolP("no-follow", "n", false, "Show history and exit (no live stream)")
	plain := flag.BoolP("plain", "p", false, "Force plain text output (no TUI)")
	window := flag.StringP("window", "w", "", "Window filter (-1 for all, N for specific)")
	// keep-sorted end
	flag.Parse()

	winFilter := resolveWindowFilter(*window)
	plainMode := *plain || *noFollow || !isatty.IsTerminal(os.Stdout.Fd())

	ch := make(chan LogEntry, 256)
	live := !*noFollow && (!plainMode || *history == "")
	go streamLogs(*history, live, ch)

	if plainMode {
		for entry := range ch {
			if winFilter != "" && entry.Window != "" && entry.Window != winFilter {
				continue
			}
			if !matchLevel(*level, entry) {
				continue
			}
			if _, err := fmt.Println(formatEntry(entry)); err != nil {
				return
			}
		}
		return
	}

	p := tea.NewProgram(newModel(ch, winFilter, *level, *history), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
