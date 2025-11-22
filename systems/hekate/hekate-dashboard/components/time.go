package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type TimeModel struct {
	currentTime    time.Time
	systemTimeInfo string
	err            error
}

type timeTickMsg time.Time
type timeInfoMsg struct {
	info string
	err  error
}

func NewTimeModel() TimeModel {
	return TimeModel{}
}

func (m TimeModel) Init() tea.Cmd {
	return tea.Batch(
		m.tick(),
		m.fetchTimeInfo(),
	)
}

func (m TimeModel) tick() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return timeTickMsg(t)
	})
}

func (m TimeModel) fetchTimeInfo() tea.Cmd {
	return func() tea.Msg {
		info, err := services.GetSystemTimeInfo()
		return timeInfoMsg{info: info, err: err}
	}
}

func (m TimeModel) Update(msg tea.Msg) (TimeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case timeTickMsg:
		m.currentTime = time.Time(msg)
		return m, m.tick()

	case timeInfoMsg:
		m.systemTimeInfo = msg.info
		m.err = msg.err
		return m, nil
	}

	return m, nil
}

func (m TimeModel) View() string {
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240")).
		Padding(0, 1).
		Margin(1, 0)

	errorStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("9"))

	timeStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(1, 2)

	header := headerStyle.Render("System Time")

	var currentTimeDisplay string
	if !m.currentTime.IsZero() {
		currentTimeDisplay = fmt.Sprintf("%s\n%s",
			m.currentTime.Format("Monday, January 2, 2006"),
			m.currentTime.Format("15:04:05 MST"),
		)
	} else {
		currentTimeDisplay = time.Now().Format("Monday, January 2, 2006\n15:04:05 MST")
	}

	timeDisplay := timeStyle.Render(currentTimeDisplay)

	var systemInfo string
	if m.err != nil {
		systemInfo = boxStyle.Render(errorStyle.Render("Error: " + m.err.Error()))
	} else if m.systemTimeInfo != "" {
		systemInfo = boxStyle.Render(m.systemTimeInfo)
	} else {
		systemInfo = boxStyle.Render("Loading system time information...")
	}

	return header + "\n" + timeDisplay + "\n" + systemInfo
}
