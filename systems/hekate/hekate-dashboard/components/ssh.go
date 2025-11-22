package components

import (
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type SSHModel struct {
	viewport    viewport.Model
	content     string
	ready       bool
	err         error
	initialized bool
}

type sshLogsMsg struct {
	content string
	err     error
}

type sshTickMsg time.Time
type sshTimeoutMsg time.Time

func NewSSHModel() SSHModel {
	return SSHModel{
		viewport: viewport.New(80, 20),
	}
}

func (m SSHModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchLogs(),
		m.tick(),
		m.timeout(),
	)
}

func (m SSHModel) timeout() tea.Cmd {
	return tea.Tick(time.Second*10, func(t time.Time) tea.Msg {
		return sshTimeoutMsg(t)
	})
}

func (m SSHModel) tick() tea.Cmd {
	return tea.Tick(time.Second*5, func(t time.Time) tea.Msg {
		return sshTickMsg(t)
	})
}

func (m SSHModel) fetchLogs() tea.Cmd {
	return func() tea.Msg {
		content, err := services.GetSSHLogs()
		return sshLogsMsg{content: content, err: err}
	}
}

func (m SSHModel) Update(msg tea.Msg) (SSHModel, tea.Cmd) {
	var cmd tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		if !m.ready {
			m.viewport = viewport.New(msg.Width-4, msg.Height-10)
			m.ready = true
		} else {
			m.viewport.Width = msg.Width - 4
			m.viewport.Height = msg.Height - 10
		}

	case sshTickMsg:
		return m, tea.Batch(m.fetchLogs(), m.tick())

	case sshLogsMsg:
		m.content = msg.content
		m.err = msg.err
		m.initialized = true
		m.viewport.SetContent(m.content)
		m.viewport.GotoBottom()
		return m, nil

	case sshTimeoutMsg:
		if !m.initialized {
			m.content = "Timeout: Failed to load SSH logs after 10 seconds. Check permissions and log file existence."
			m.initialized = true
			m.viewport.SetContent(m.content)
		}
		return m, nil
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

func (m SSHModel) View() string {
	if m.err != nil {
		return lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Render("Error loading SSH logs: " + m.err.Error())
	}

	if !m.ready {
		return "Loading SSH logs..."
	}

	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

	header := headerStyle.Render("SSH Access Logs")

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Padding(1, 0, 0, 1)
	help := helpStyle.Render("↑↓: scroll • g/G: top/bottom")

	return header + "\n\n" + m.viewport.View() + "\n" + help
}
