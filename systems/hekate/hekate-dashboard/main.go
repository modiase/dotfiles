package main

import (
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/components"
)

type tab int

const (
	statusTab tab = iota
	sshTab
	wireguardTab
	healthTab
	networkTab
	timeTab
)

type model struct {
	activeTab tab
	width     int
	height    int

	statusModel    components.StatusModel
	sshModel       components.SSHModel
	wireguardModel components.WireGuardModel
	healthModel    components.HealthModel
	networkModel   components.NetworkModel
	timeModel      components.TimeModel
}

func initialModel() model {
	return model{
		activeTab:      statusTab,
		statusModel:    components.NewStatusModel(),
		sshModel:       components.NewSSHModel(),
		wireguardModel: components.NewWireGuardModel(),
		healthModel:    components.NewHealthModel(),
		networkModel:   components.NewNetworkModel(),
		timeModel:      components.NewTimeModel(),
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.statusModel.Init(),
		m.sshModel.Init(),
		m.wireguardModel.Init(),
		m.healthModel.Init(),
		m.networkModel.Init(),
		m.timeModel.Init(),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "1":
			m.activeTab = statusTab
		case "2":
			m.activeTab = sshTab
		case "3":
			m.activeTab = wireguardTab
		case "4":
			m.activeTab = healthTab
		case "5":
			m.activeTab = networkTab
		case "6":
			m.activeTab = timeTab
		case "left":
			if m.activeTab > statusTab {
				m.activeTab--
			}
		case "right":
			if m.activeTab < timeTab {
				m.activeTab++
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	}

	m.statusModel, cmd = m.statusModel.Update(msg)
	cmds = append(cmds, cmd)

	m.sshModel, cmd = m.sshModel.Update(msg)
	cmds = append(cmds, cmd)

	m.wireguardModel, cmd = m.wireguardModel.Update(msg)
	cmds = append(cmds, cmd)

	m.healthModel, cmd = m.healthModel.Update(msg)
	cmds = append(cmds, cmd)

	m.networkModel, cmd = m.networkModel.Update(msg)
	cmds = append(cmds, cmd)

	m.timeModel, cmd = m.timeModel.Update(msg)
	cmds = append(cmds, cmd)

	return m, tea.Batch(cmds...)
}

func (m model) View() string {
	var tabStyle = lipgloss.NewStyle().
		Padding(0, 2).
		Border(lipgloss.RoundedBorder(), false, false, true, false)

	var activeTabStyle = tabStyle.Copy().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		BorderForeground(lipgloss.Color("99"))

	var inactiveTabStyle = tabStyle.Copy().
		Foreground(lipgloss.Color("240")).
		BorderForeground(lipgloss.Color("240"))

	tabs := []string{}
	tabNames := []string{"Status", "SSH", "WireGuard", "Health", "Network", "Time"}
	for i, name := range tabNames {
		if tab(i) == m.activeTab {
			tabs = append(tabs, activeTabStyle.Render(name))
		} else {
			tabs = append(tabs, inactiveTabStyle.Render(name))
		}
	}

	header := lipgloss.JoinHorizontal(lipgloss.Top, tabs...)

	var content string
	switch m.activeTab {
	case statusTab:
		content = m.statusModel.View()
	case sshTab:
		content = m.sshModel.View()
	case wireguardTab:
		content = m.wireguardModel.View()
	case healthTab:
		content = m.healthModel.View()
	case networkTab:
		content = m.networkModel.View()
	case timeTab:
		content = m.timeModel.View()
	}

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Padding(1, 0, 0, 2)
	help := helpStyle.Render("← → / 1-6: switch tabs • q: quit")

	return fmt.Sprintf("%s\n\n%s\n%s", header, content, help)
}

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
