package components

import (
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type DNSModel struct {
	viewport    viewport.Model
	content     string
	lines       []string
	ready       bool
	err         error
	initialized bool
	search      SearchState
}

type dnsLogsMsg struct {
	content string
	err     error
}

type dnsTickMsg time.Time
type dnsSearchDebounceMsg time.Time

func NewDNSModel() DNSModel {
	return DNSModel{
		viewport: viewport.New(80, 20),
		search:   NewSearchState(),
	}
}

func (m DNSModel) IsSearchActive() bool {
	return m.search.Active
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

func (m DNSModel) searchDebounce() tea.Cmd {
	return tea.Tick(150*time.Millisecond, func(t time.Time) tea.Msg {
		return dnsSearchDebounceMsg(t)
	})
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
		m.lines = strings.Split(m.content, "\n")
		m.err = msg.err
		m.initialized = true
		if m.search.Query != "" {
			m.search.FindMatches(m.lines)
			m.viewport.SetContent(m.search.HighlightContent(m.lines))
		} else {
			m.viewport.SetContent(m.content)
			m.viewport.GotoBottom()
		}
		return m, nil

	case dnsSearchDebounceMsg:
		if m.search.NeedsUpdate() {
			m.search.FindMatches(m.lines)
			m.viewport.SetContent(m.search.HighlightContent(m.lines))
			if line := m.search.CurrentLine(); line >= 0 {
				m.viewport.SetYOffset(line)
			}
		}
		if m.search.Active {
			return m, m.searchDebounce()
		}
		return m, nil

	case tea.KeyMsg:
		if m.search.Active {
			switch msg.String() {
			case "enter":
				m.search.Active = false
				return m, nil
			case "esc":
				m.search.Reset()
				m.viewport.SetContent(m.content)
				return m, nil
			case "backspace":
				if len(m.search.Query) > 0 {
					m.search.Query = m.search.Query[:len(m.search.Query)-1]
				}
				return m, nil
			default:
				if len(msg.String()) == 1 && msg.String() != " " {
					m.search.Query += msg.String()
				} else if msg.String() == " " {
					m.search.Query += " "
				}
				return m, nil
			}
		} else {
			switch msg.String() {
			case "/":
				m.search.Active = true
				m.search.Direction = 1
				m.search.Query = ""
				return m, m.searchDebounce()
			case "?":
				m.search.Active = true
				m.search.Direction = -1
				m.search.Query = ""
				return m, m.searchDebounce()
			case "n":
				if line := m.search.NextMatch(); line >= 0 {
					m.viewport.SetYOffset(line)
				}
				return m, nil
			case "N":
				if line := m.search.PrevMatch(); line >= 0 {
					m.viewport.SetYOffset(line)
				}
				return m, nil
			}
		}
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

	helpText := "↑↓: scroll • g/G: top/bottom • /?: search • n/N: next/prev match"
	if m.search.Active {
		helpText = "Enter/Esc: close search"
	}
	help := helpStyle.Render(helpText)

	searchBar := ""
	if m.search.Active || m.search.Query != "" {
		searchBar = "\n" + m.search.RenderSearchBarFormatted(m.viewport.Width)
	}

	return header + "\n\n" + m.viewport.View() + "\n" + help + searchBar
}
