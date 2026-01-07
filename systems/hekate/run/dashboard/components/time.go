package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type TimeModel struct {
	currentTime time.Time
}

type timeTickMsg time.Time

func NewTimeModel() TimeModel {
	return TimeModel{}
}

func (m TimeModel) Init() tea.Cmd {
	return m.tick()
}

func (m TimeModel) tick() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return timeTickMsg(t)
	})
}

func (m TimeModel) Update(msg tea.Msg) (TimeModel, tea.Cmd) {
	switch msg := msg.(type) {
	case timeTickMsg:
		m.currentTime = time.Time(msg)
		return m, m.tick()
	}

	return m, nil
}

func (m TimeModel) View() string {
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

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

	return header + "\n" + timeDisplay
}
