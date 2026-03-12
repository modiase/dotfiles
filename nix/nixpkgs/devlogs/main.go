package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/mattn/go-isatty"
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
	history := flag.String("history", "", "Show history (e.g. 1h, 30m, 2d)")
	window := flag.String("w", "", "Window filter (-1 for all, N for specific)")
	flag.Parse()

	winFilter := resolveWindowFilter(*window)

	ch := make(chan LogEntry, 256)
	go streamLogs(*history, ch)

	if !isatty.IsTerminal(os.Stdout.Fd()) {
		for entry := range ch {
			if winFilter != "" && entry.Window != "" && entry.Window != winFilter {
				continue
			}
			fmt.Println(entry.Raw)
		}
		return
	}

	p := tea.NewProgram(newModel(ch, winFilter, *history != ""), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}
