package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/components"
	"github.com/moye/hekate-dashboard/services"
)

type tab int

const (
	statusTab tab = iota
	sshTab
	wireguardTab
	dnsTab
	firewallTab
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
	dnsModel       components.DNSModel
	firewallModel  components.FirewallModel
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
		dnsModel:       components.NewDNSModel(),
		firewallModel:  components.NewFirewallModel(),
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
		m.dnsModel.Init(),
		m.firewallModel.Init(),
		m.healthModel.Init(),
		m.networkModel.Init(),
		m.timeModel.Init(),
	)
}

func (m model) isSearchActive() bool {
	switch m.activeTab {
	case sshTab:
		return m.sshModel.IsSearchActive()
	case dnsTab:
		return m.dnsModel.IsSearchActive()
	case firewallTab:
		return m.firewallModel.IsSearchActive()
	}
	return false
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmd tea.Cmd
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		if !m.isSearchActive() {
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
				m.activeTab = dnsTab
			case "5":
				m.activeTab = firewallTab
			case "6":
				m.activeTab = healthTab
			case "7":
				m.activeTab = networkTab
			case "8":
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

	m.dnsModel, cmd = m.dnsModel.Update(msg)
	cmds = append(cmds, cmd)

	m.firewallModel, cmd = m.firewallModel.Update(msg)
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
	tabNames := []string{"Status", "SSH", "WireGuard", "DNS", "Firewall", "Health", "Network", "Time"}
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
	case dnsTab:
		content = m.dnsModel.View()
	case firewallTab:
		content = m.firewallModel.View()
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
	help := helpStyle.Render("← → / 1-8: switch tabs • /?: search • q: quit")

	return fmt.Sprintf("%s\n\n%s\n%s", header, content, help)
}

func main() {
	demo := flag.Bool("demo", false, "Run with simulated streaming data")
	flag.Parse()

	if *demo {
		services.SetDemoMode(true)
	}

	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
