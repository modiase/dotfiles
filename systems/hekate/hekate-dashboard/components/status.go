package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type ServiceStatus struct {
	Name   string
	Active bool
	Uptime string
}

type StatusModel struct {
	services []ServiceStatus
	err      error
}

type statusTickMsg time.Time

func NewStatusModel() StatusModel {
	return StatusModel{
		services: []ServiceStatus{},
	}
}

func (m StatusModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchStatus(),
		m.tick(),
	)
}

func (m StatusModel) tick() tea.Cmd {
	return tea.Tick(time.Second*5, func(t time.Time) tea.Msg {
		return statusTickMsg(t)
	})
}

func (m StatusModel) fetchStatus() tea.Cmd {
	return func() tea.Msg {
		serviceNames := []string{
			"wireguard-wg0",
			"sshd",
			"avahi-daemon",
		}

		statuses := []ServiceStatus{}
		for _, name := range serviceNames {
			active, uptime, err := services.GetServiceStatus(name)
			if err != nil {
				statuses = append(statuses, ServiceStatus{
					Name:   name,
					Active: false,
					Uptime: "error",
				})
				continue
			}

			statuses = append(statuses, ServiceStatus{
				Name:   name,
				Active: active,
				Uptime: uptime,
			})
		}

		return statusUpdateMsg{statuses: statuses}
	}
}

type statusUpdateMsg struct {
	statuses []ServiceStatus
	err      error
}

func (m StatusModel) Update(msg tea.Msg) (StatusModel, tea.Cmd) {
	switch msg := msg.(type) {
	case statusTickMsg:
		return m, tea.Batch(m.fetchStatus(), m.tick())

	case statusUpdateMsg:
		m.services = msg.statuses
		m.err = msg.err
		return m, nil
	}

	return m, nil
}

func (m StatusModel) View() string {
	if m.err != nil {
		return fmt.Sprintf("Error loading services: %v", m.err)
	}

	if len(m.services) == 0 {
		return "Loading services..."
	}

	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

	activeStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("10")).
		Bold(true)

	inactiveStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("9")).
		Bold(true)

	nameStyle := lipgloss.NewStyle().
		Width(25).
		Padding(0, 1)

	uptimeStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240"))

	s := headerStyle.Render("System Services Status") + "\n\n"

	for _, svc := range m.services {
		status := "●"
		statusStyle := inactiveStyle
		if svc.Active {
			statusStyle = activeStyle
		}

		line := fmt.Sprintf("%s %s %s",
			statusStyle.Render(status),
			nameStyle.Render(svc.Name),
			uptimeStyle.Render(svc.Uptime),
		)
		s += line + "\n"
	}

	return s
}
