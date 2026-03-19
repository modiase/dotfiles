package main

import (
	"bufio"
	"flag"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/neovim/go-client/nvim"
)

type providerConfig struct {
	dialogPattern string
	keys          map[string]string
}

var providers = map[string]providerConfig{
	"claude": {
		dialogPattern: "manually approve edits",
		keys: map[string]string{
			"accept_clear":  "1",
			"accept_auto":   "2",
			"accept_manual": "3",
			"reject":        "4",
		},
	},
	"gemini": {
		dialogPattern: "Do you want to",
		keys: map[string]string{
			"accept_auto":   "1",
			"accept_manual": "2",
			"reject":        "3",
		},
	},
}

func clog(level, msg string) {
	log.Printf("[devlogs] %s agents-plan-responder: %s", strings.ToUpper(level), msg)
}

func tmuxCapturePane(pane string) string {
	out, err := exec.Command("tmux", "capture-pane", "-t", pane, "-p").Output()
	if err != nil {
		clog("error", fmt.Sprintf("tmux capture-pane failed: %v", err))
		return ""
	}
	return string(out)
}

func tmuxPaneContains(pane, pattern string) bool {
	return strings.Contains(tmuxCapturePane(pane), pattern)
}

func tmuxSendKeys(pane string, keys ...string) error {
	args := append([]string{"send-keys", "-t", pane}, keys...)
	return exec.Command("tmux", args...).Run()
}

func tmuxSendLiteral(pane, text string) error {
	return exec.Command("tmux", "send-keys", "-t", pane, "-l", text).Run()
}

func nvimClosePlanByFifo(socket, provider, fifo string) {
	clog("debug", fmt.Sprintf("nvim close: dialling socket=%s", socket))
	v, err := nvim.Dial(socket)
	if err != nil {
		clog("warning", fmt.Sprintf("nvim dial failed: %v", err))
		return
	}
	defer func() { _ = v.Close() }()

	lua := fmt.Sprintf("require('utils.%s-plan').close_by_fifo('%s')", provider, fifo)
	clog("debug", fmt.Sprintf("nvim close: executing lua=%s", lua))
	if err := v.ExecLua(lua, nil); err != nil {
		clog("warning", fmt.Sprintf("close_by_fifo failed: %v", err))
	}
	clog("info", fmt.Sprintf("nvim close: plan tab closed provider=%s", provider))
}

func readFifo(fifo string) <-chan string {
	ch := make(chan string, 1)
	go func() {
		clog("debug", fmt.Sprintf("fifo reader: blocking on open fifo=%s", fifo))
		f, err := os.Open(fifo)
		if err != nil {
			clog("error", fmt.Sprintf("fifo open failed: %v", err))
			close(ch)
			return
		}
		defer func() { _ = f.Close() }()
		clog("debug", "fifo reader: opened, waiting for data")

		scanner := bufio.NewScanner(f)
		if scanner.Scan() {
			ch <- scanner.Text()
		}
		clog("debug", "fifo reader: done")
		close(ch)
	}()
	return ch
}

func watchExternalDismissal(pane, pattern string) <-chan struct{} {
	ch := make(chan struct{}, 1)
	go func() {
		clog("debug", fmt.Sprintf("pane watcher: started pane=%s pattern=%q", pane, pattern))
		dialogSeen := false
		for {
			time.Sleep(500 * time.Millisecond)
			has := tmuxPaneContains(pane, pattern)
			if has && !dialogSeen {
				clog("debug", "pane watcher: dialog appeared")
				dialogSeen = true
			} else if !has && dialogSeen {
				clog("debug", "pane watcher: dialog disappeared (external dismissal)")
				ch <- struct{}{}
				return
			}
		}
	}()
	return ch
}

func pollForDialog(pane, pattern string, timeout time.Duration) bool {
	clog("debug", fmt.Sprintf("pollForDialog: pane=%s timeout=%v", pane, timeout))
	deadline := time.After(timeout)
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-deadline:
			clog("debug", "pollForDialog: deadline reached")
			return false
		case <-ticker.C:
			if tmuxPaneContains(pane, pattern) {
				clog("debug", "pollForDialog: pattern found")
				return true
			}
		}
	}
}

func handleResponse(response, pane string, cfg providerConfig) {
	action := response
	reason := ""
	if strings.HasPrefix(response, "reject:") {
		action = "reject"
		reason = strings.TrimPrefix(response, "reject:")
	}

	key, ok := cfg.keys[action]
	if !ok {
		clog("error", fmt.Sprintf("unknown action: %s", action))
		return
	}

	clog("info", fmt.Sprintf("waiting for dialog action=%s key=%s", action, key))

	if !pollForDialog(pane, cfg.dialogPattern, 30*time.Second) {
		clog("error", "timed out waiting for dialog after 30s")
		content := tmuxCapturePane(pane)
		if len(content) > 200 {
			content = content[:200]
		}
		clog("error", fmt.Sprintf("pane content at timeout: %q", content))
		return
	}

	clog("info", fmt.Sprintf("dialog found, sending key=%s pane=%s", key, pane))
	if err := tmuxSendLiteral(pane, key); err != nil {
		clog("error", fmt.Sprintf("send key failed: %v", err))
		return
	}

	if action == "reject" {
		clog("debug", fmt.Sprintf("reject: sending reason=%q", reason))
		time.Sleep(200 * time.Millisecond)
		if err := tmuxSendKeys(pane, "Enter"); err != nil {
			clog("error", fmt.Sprintf("send Enter failed: %v", err))
			return
		}
		time.Sleep(200 * time.Millisecond)
		if err := tmuxSendLiteral(pane, reason); err != nil {
			clog("error", fmt.Sprintf("send reason failed: %v", err))
			return
		}
		if err := tmuxSendKeys(pane, "Enter"); err != nil {
			clog("error", fmt.Sprintf("send final Enter failed: %v", err))
		}
	}
	clog("info", fmt.Sprintf("response handled action=%s", action))
}

func main() {
	fifo := flag.String("fifo", "", "Path to FIFO")
	pane := flag.String("pane", "", "Tmux pane ID")
	provider := flag.String("provider", "", "Provider: claude or gemini")
	nvimSocket := flag.String("nvim-socket", "", "Neovim socket path")
	flag.Parse()

	if *fifo == "" || *pane == "" || *provider == "" || *nvimSocket == "" {
		fmt.Fprintf(os.Stderr, "Usage: plan-responder --fifo PATH --pane PANE --provider PROVIDER --nvim-socket SOCKET\n")
		os.Exit(1)
	}

	cfg, ok := providers[*provider]
	if !ok {
		fmt.Fprintf(os.Stderr, "Unknown provider: %s\n", *provider)
		os.Exit(1)
	}

	defer func() {
		clog("debug", fmt.Sprintf("cleanup: removing fifo=%s", *fifo))
		_ = os.Remove(*fifo)
	}()

	clog("info", fmt.Sprintf("started fifo=%s pane=%s provider=%s socket=%s", *fifo, *pane, *provider, *nvimSocket))

	fifoCh := readFifo(*fifo)
	dismissCh := watchExternalDismissal(*pane, cfg.dialogPattern)
	timeout := time.After(300 * time.Second)

	select {
	case response, ok := <-fifoCh:
		if !ok {
			clog("warning", "fifo closed without response")
			return
		}
		clog("info", fmt.Sprintf("received response: %s", response))
		handleResponse(response, *pane, cfg)

	case <-dismissCh:
		clog("info", "dialog dismissed externally, closing nvim plan tab")
		nvimClosePlanByFifo(*nvimSocket, *provider, *fifo)

	case <-timeout:
		clog("info", "timed out, closing nvim plan tab")
		nvimClosePlanByFifo(*nvimSocket, *provider, *fifo)
	}
}
