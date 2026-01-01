package components

import (
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type DNSModel struct {
	viewport    viewport.Model
	content     string
	ready       bool
	err         error
	initialized bool
}

type dnsLogsMsg struct {
	content string
	err     error
}

type dnsTickMsg time.Time

func NewDNSModel() DNSModel {
	return DNSModel{
		viewport: viewport.New(80, 20),
	}
}

func (m DNSModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchLogs(),
		m.tick(),
	)
}

func (m DNSModel) tick() tea.Cmd {
	return tea.Tick(time.Second*3, func(t time.Time) tea.Msg {
		return dnsTickMsg(t)
	})
}

func (m DNSModel) fetchLogs() tea.Cmd {
	return func() tea.Msg {
		content, err := services.GetDNSLogs()
		return dnsLogsMsg{content: content, err: err}
	}
}

func (m DNSModel) Update(msg tea.Msg) (DNSModel, tea.Cmd) {
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

	case dnsTickMsg:
		return m, tea.Batch(m.fetchLogs(), m.tick())

	case dnsLogsMsg:
		m.content = msg.content
		m.err = msg.err
		m.initialized = true
		m.viewport.SetContent(m.content)
		m.viewport.GotoBottom()
		return m, nil
	}

	m.viewport, cmd = m.viewport.Update(msg)
	return m, cmd
}

func (m DNSModel) View() string {
	if m.err != nil {
		return lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Render("Error loading DNS logs: " + m.err.Error())
	}

	if !m.ready {
		return "Loading DNS logs..."
	}

	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

	header := headerStyle.Render("DNS Query Logs")

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Padding(1, 0, 0, 1)
	help := helpStyle.Render("↑↓: scroll • g/G: top/bottom")

	return header + "\n\n" + m.viewport.View() + "\n" + help
}
