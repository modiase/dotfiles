package main

import (
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("99"))
	errorStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("9"))
	warnStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("11"))
	infoStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))
	debugStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("8"))
	dimStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))
	helpStyle  = lipgloss.NewStyle().Foreground(lipgloss.Color("245"))

	historyPresets = []string{"30m", "1h", "6h", "1d", "2d", "7d"}
	levelCycle     = []string{"debug", "info", "warn", "error"}
)

type historyEntriesMsg []LogEntry

type model struct {
	entries         []LogEntry
	filtered        []int
	filter          textinput.Model
	filtering       bool
	follow          bool
	offset          int
	width           int
	height          int
	logCh           chan LogEntry
	levelFilter     string
	windowFilter    string
	historyIdx      int
	fetchingHistory bool
	spinner         spinner.Model
}

func newModel(ch chan LogEntry, windowFilter string, levelFilter string, historyDuration string) model {
	ti := textinput.New()
	ti.Placeholder = "type to filter..."
	ti.CharLimit = 256

	historyIdx := -1
	for i, p := range historyPresets {
		if p == historyDuration {
			historyIdx = i
			break
		}
	}

	sp := spinner.New()
	sp.Spinner = spinner.Dot
	sp.Style = dimStyle

	return model{
		filter:       ti,
		follow:       historyDuration == "",
		levelFilter:  levelFilter,
		logCh:        ch,
		windowFilter: windowFilter,
		historyIdx:   historyIdx,
		spinner:      sp,
	}
}

func (m model) Init() tea.Cmd {
	return waitForLog(m.logCh)
}

type streamDoneMsg struct{}

func waitForLog(ch chan LogEntry) tea.Cmd {
	return func() tea.Msg {
		entry, ok := <-ch
		if !ok {
			return streamDoneMsg{}
		}
		return logLineMsg(entry)
	}
}

func (m *model) matchWindow(e LogEntry) bool {
	if m.windowFilter == "" {
		return true
	}
	if e.Window == "" {
		return true
	}
	return e.Window == m.windowFilter
}

func (m *model) refilter() {
	m.filtered = m.filtered[:0]
	query := m.filter.Value()
	for i, e := range m.entries {
		if m.matchWindow(e) && matchLevel(m.levelFilter, e) && matchFilter(query, formatEntry(e)) {
			m.filtered = append(m.filtered, i)
		}
	}
}

func (m *model) viewportHeight() int {
	return m.height - 4
}

func (m *model) clampOffset() {
	vh := m.viewportHeight()
	if vh <= 0 {
		m.offset = 0
		return
	}
	maxOffset := len(m.filtered) - vh
	if maxOffset < 0 {
		maxOffset = 0
	}
	if m.offset > maxOffset {
		m.offset = maxOffset
	}
	if m.offset < 0 {
		m.offset = 0
	}
}

func (m *model) scrollToBottom() {
	vh := m.viewportHeight()
	maxOffset := len(m.filtered) - vh
	if maxOffset < 0 {
		maxOffset = 0
	}
	m.offset = maxOffset
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.clampOffset()
		if m.follow {
			m.scrollToBottom()
		}
		return m, nil

	case streamDoneMsg:
		return m, nil

	case spinner.TickMsg:
		if m.fetchingHistory {
			var cmd tea.Cmd
			m.spinner, cmd = m.spinner.Update(msg)
			return m, cmd
		}
		return m, nil

	case historyEntriesMsg:
		m.fetchingHistory = false
		m.entries = []LogEntry(msg)
		m.refilter()
		m.follow = false
		m.offset = 0
		return m, nil

	case logLineMsg:
		entry := LogEntry(msg)
		m.entries = append(m.entries, entry)
		if m.matchWindow(entry) && matchLevel(m.levelFilter, entry) && matchFilter(m.filter.Value(), formatEntry(entry)) {
			m.filtered = append(m.filtered, len(m.entries)-1)
		}
		if m.follow {
			m.scrollToBottom()
		}
		return m, waitForLog(m.logCh)

	case tea.KeyMsg:
		if m.filtering {
			switch msg.String() {
			case "enter":
				m.filtering = false
				m.filter.Blur()
				return m, nil
			case "esc":
				m.filtering = false
				m.filter.Blur()
				m.filter.SetValue("")
				m.refilter()
				if m.follow {
					m.scrollToBottom()
				}
				return m, nil
			default:
				var cmd tea.Cmd
				m.filter, cmd = m.filter.Update(msg)
				m.refilter()
				if m.follow {
					m.scrollToBottom()
				}
				return m, cmd
			}
		}

		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "/":
			m.filtering = true
			m.filter.Focus()
			return m, textinput.Blink
		case "esc":
			m.filter.SetValue("")
			m.refilter()
			if m.follow {
				m.scrollToBottom()
			}
			return m, nil
		case "a":
			if m.windowFilter != "" {
				m.windowFilter = ""
			} else if pane := os.Getenv("TMUX_PANE"); pane != "" {
				out, err := exec.Command("tmux", "display-message", "-t", pane, "-p", "#{window_index}").Output()
				if err == nil {
					m.windowFilter = strings.TrimSpace(string(out))
				}
			}
			m.refilter()
			if m.follow {
				m.scrollToBottom()
			}
			return m, nil
		case "c":
			m.entries = m.entries[:0]
			m.filtered = m.filtered[:0]
			m.offset = 0
			m.historyIdx = -1
			return m, nil
		case "l":
			for i, lv := range levelCycle {
				if lv == m.levelFilter {
					m.levelFilter = levelCycle[(i+1)%len(levelCycle)]
					m.refilter()
					if m.follow {
						m.scrollToBottom()
					}
					return m, nil
				}
			}
			m.levelFilter = levelCycle[0]
			m.refilter()
			if m.follow {
				m.scrollToBottom()
			}
			return m, nil
		case "H":
			if m.fetchingHistory {
				return m, nil
			}
			m.historyIdx = (m.historyIdx + 1) % len(historyPresets)
			m.fetchingHistory = true
			return m, tea.Batch(fetchHistory(historyPresets[m.historyIdx]), m.spinner.Tick)
		case "f":
			m.follow = !m.follow
			if m.follow {
				m.scrollToBottom()
			}
			return m, nil
		case "j", "down":
			m.follow = false
			m.offset++
			m.clampOffset()
			return m, nil
		case "k", "up":
			m.follow = false
			if m.offset > 0 {
				m.offset--
			}
			return m, nil
		case "g", "home":
			m.follow = false
			m.offset = 0
			return m, nil
		case "G", "end":
			m.follow = true
			m.scrollToBottom()
			return m, nil
		case "pgdown", "ctrl+d":
			m.follow = false
			vh := m.viewportHeight()
			m.offset += vh / 2
			m.clampOffset()
			return m, nil
		case "pgup", "ctrl+u":
			m.follow = false
			vh := m.viewportHeight()
			m.offset -= vh / 2
			if m.offset < 0 {
				m.offset = 0
			}
			return m, nil
		}
	}
	return m, nil
}

func renderEntry(e LogEntry, width int) string {
	var levelStr string
	switch strings.ToUpper(e.Level) {
	case "ERROR":
		levelStr = errorStyle.Render("ERROR")
	case "WARN":
		levelStr = warnStyle.Render("WARN ")
	case "INFO":
		levelStr = infoStyle.Render("INFO ")
	case "DEBUG":
		levelStr = debugStyle.Render("DEBUG")
	default:
		levelStr = dimStyle.Render(fmt.Sprintf("%-5s", e.Level))
	}

	ts := dimStyle.Render(e.Timestamp)

	line := fmt.Sprintf("%s %s %s", ts, levelStr, e.Message)
	if width > 0 && lipgloss.Width(line) > width {
		runes := []rune(line)
		if len(runes) > width-1 {
			line = string(runes[:width-1]) + "…"
		}
	}
	return line
}

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return "loading..."
	}

	var b strings.Builder

	followTag := dimStyle.Render("[paused]")
	if m.follow {
		followTag = lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Render("[follow]")
	}
	titleName := "devlogs"
	if m.windowFilter != "" {
		titleName = fmt.Sprintf("devlogs(@%s)", m.windowFilter)
	}
	levelTag := ""
	if m.levelFilter != "" {
		levelTag = dimStyle.Render("[" + strings.ToUpper(m.levelFilter) + "+]")
	}

	historyTag := ""
	if m.historyIdx >= 0 {
		ht := historyPresets[m.historyIdx]
		if m.fetchingHistory {
			ht += " " + m.spinner.View()
		}
		historyTag = dimStyle.Render("[" + ht + "]")
	}

	tags := followTag
	for _, t := range []string{levelTag, historyTag} {
		if t != "" {
			tags += " " + t
		}
	}

	titleLine := fmt.Sprintf(" %s %s %d entries (%d shown)",
		titleStyle.Render(titleName), tags, len(m.entries), len(m.filtered))
	b.WriteString(titleLine)
	b.WriteByte('\n')

	sep := dimStyle.Render(strings.Repeat("─", m.width))
	b.WriteString(sep)
	b.WriteByte('\n')

	vh := m.viewportHeight()
	if vh < 0 {
		vh = 0
	}
	end := m.offset + vh
	if end > len(m.filtered) {
		end = len(m.filtered)
	}
	start := m.offset
	if start > len(m.filtered) {
		start = len(m.filtered)
	}

	linesWritten := 0
	for _, idx := range m.filtered[start:end] {
		b.WriteString(renderEntry(m.entries[idx], m.width))
		b.WriteByte('\n')
		linesWritten++
	}
	for i := linesWritten; i < vh; i++ {
		b.WriteByte('\n')
	}

	b.WriteString(sep)
	b.WriteByte('\n')

	if m.filtering {
		b.WriteString(" / ")
		b.WriteString(m.filter.View())
	} else if m.filter.Value() != "" {
		b.WriteString(helpStyle.Render(fmt.Sprintf(" / %s", m.filter.Value())))
		b.WriteString(helpStyle.Render("    esc reset  ↑↓ scroll  a all/window  l level  H history  c clear  f follow  q quit"))
	} else {
		b.WriteString(helpStyle.Render(" / filter  ↑↓ scroll  a all/window  l level  H history  c clear  f follow  q quit"))
	}

	return b.String()
}
