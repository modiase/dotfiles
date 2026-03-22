package devlogs

import (
	"fmt"
	"os"
	"os/exec"
	"strings"
)

type Logger struct {
	component string
	instance  string
	window    string
}

func NewLogger(component string) *Logger {
	if component == "" {
		component = os.Getenv("DEVLOGS_COMPONENT")
	}
	if component == "" {
		component = "unknown"
	}
	instance := os.Getenv("DEVLOGS_INSTANCE")
	if instance == "" {
		instance = "-"
	}
	l := &Logger{component: component, instance: instance}
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
	tag := fmt.Sprintf("%s{%s}", l.component, l.instance)
	if l.window != "" {
		tag = fmt.Sprintf("%s{%s}(@%s)", l.component, l.instance, l.window)
	}
	formatted := fmt.Sprintf("[devlogs] %s %s: %s", strings.ToUpper(level), tag, msg)
	_ = exec.Command("logger", "-t", "devlogs", "-p", "user."+level, formatted).Run()
}
