package main

import (
	"bufio"
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"
	"syscall"

	"github.com/neovim/go-client/nvim"
)

func clog(level, msg string) {
	log.Printf("[devlogs] %s gemini-editor: %s", strings.ToUpper(level), msg)
}

func runTmuxNvimSelect() (socket, targetPane string) {
	cmd := exec.Command("tmux-nvim-select")
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return "", ""
	}
	scanner := bufio.NewScanner(strings.NewReader(string(out)))
	for scanner.Scan() {
		line := scanner.Text()
		if k, v, ok := strings.Cut(line, "="); ok {
			switch k {
			case "TARGET_PANE":
				targetPane = v
			case "NVIM_SOCKET":
				socket = v
			}
		}
	}
	return socket, targetPane
}

func fallbackNvim(file string) {
	nvimPath, err := exec.LookPath("nvim")
	if err != nil {
		clog("error", "nvim not found in PATH")
		os.Exit(1)
	}
	clog("info", "no nvim socket, launching directly")
	_ = syscall.Exec(nvimPath, []string{"nvim", file}, os.Environ())
}

func printCentered(cols int, text string) {
	pad := 0
	if cols > len(text) {
		pad = (cols - len(text)) / 2
	}
	fmt.Printf("%s%s\n", strings.Repeat(" ", pad), text)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: gemini-editor <file>\n")
		os.Exit(1)
	}
	file := os.Args[1]

	socket, targetPane := runTmuxNvimSelect()
	if socket == "" {
		fallbackNvim(file)
		return
	}

	clog("info", fmt.Sprintf("nvim found socket=%s pane=%s", socket, targetPane))

	v, err := nvim.Dial(socket)
	if err != nil {
		clog("error", fmt.Sprintf("dial failed: %v", err))
		fallbackNvim(file)
		return
	}
	defer func() { _ = v.Close() }()

	isPlan := strings.Contains(file, "/.gemini/") && strings.Contains(file, "/plans/")

	if isPlan {
		clog("info", "plan file detected, opening read-only")
	}

	if err := v.Command("tabnew " + file); err != nil {
		clog("error", fmt.Sprintf("tabnew failed: %v", err))
		os.Exit(1)
	}

	buf, err := v.CurrentBuffer()
	if err != nil {
		clog("error", fmt.Sprintf("current buffer failed: %v", err))
		os.Exit(1)
	}

	if isPlan {
		if err := v.ExecLua("require('utils.gemini-plan').setup_buffer()", nil); err != nil {
			clog("error", fmt.Sprintf("setup_buffer failed: %v", err))
		}
	} else {
		_ = v.SetBufferOption(buf, "bufhidden", "delete")
	}

	chanID := v.ChannelID()

	done := make(chan struct{})
	_ = v.RegisterHandler("gemini_editor_buf_closed", func(_ ...any) {
		close(done)
	})

	autocmd := fmt.Sprintf(
		"autocmd BufWipeout <buffer=%d> call rpcnotify(%d, 'gemini_editor_buf_closed')",
		buf, chanID,
	)
	if err := v.Command(autocmd); err != nil {
		clog("error", fmt.Sprintf("autocmd failed: %v", err))
		os.Exit(1)
	}

	if targetPane != "" {
		_ = exec.Command("tmux", "select-pane", "-t", targetPane).Run()
	}

	fmt.Print("\033[2J\033[H")
	fmt.Print("\033[?25l")

	cols := 80
	if c, err := exec.Command("tput", "cols").Output(); err == nil {
		_, _ = fmt.Sscanf(strings.TrimSpace(string(c)), "%d", &cols)
	}
	lines := 24
	if l, err := exec.Command("tput", "lines").Output(); err == nil {
		_, _ = fmt.Sscanf(strings.TrimSpace(string(l)), "%d", &lines)
	}

	fmt.Print(strings.Repeat("\n", lines*2/5))

	label := "Editing file in nvim..."
	if isPlan {
		label = "Reviewing plan in nvim..."
	}

	printCentered(cols, fmt.Sprintf("\033[1;38;5;212m%s\033[0m", label))
	fmt.Println()
	printCentered(cols, "\033[2mClose the buffer to return to Gemini CLI\033[0m")

	<-done

	fmt.Print("\033[?25h\033[2J\033[H")
}
