package devlogs

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Logger struct {
	component string
	window    string
}

func NewLogger(component string) *Logger {
	l := &Logger{component: component}
	if pane := os.Getenv("TMUX_PANE"); pane != "" {
		out, err := exec.Command("tmux", "display-message", "-t", pane, "-p", "#{window_index}").Output()
		if err == nil {
			l.window = strings.TrimSpace(string(out))
		}
	}
	return l
}

func (l *Logger) Debug(msg string) { l.log("debug", msg) }
func (l *Logger) Info(msg string)  { l.log("info", msg) }
func (l *Logger) Warn(msg string)  { l.log("warning", msg) }
func (l *Logger) Error(msg string) { l.log("err", msg) }

func (l *Logger) log(level, msg string) {
	tag := l.component
	if l.window != "" {
		tag = fmt.Sprintf("%s(@%s)", l.component, l.window)
	}
	formatted := fmt.Sprintf("[devlogs] %s %s: %s", strings.ToUpper(level), tag, msg)
	// Errors silently suppressed, matching Python/shell behaviour
	_ = exec.Command("logger", "-t", "devlogs", "-p", "user."+level, formatted).Run()
}
