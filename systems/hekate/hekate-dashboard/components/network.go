package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

type NetworkModel struct {
	wg0Info     string
	eth0Info    string
	initialized bool
}

type networkMsg struct {
	wg0  string
	eth0 string
}

type networkTickMsg time.Time
type networkTimeoutMsg time.Time

func NewNetworkModel() NetworkModel {
	return NetworkModel{}
}

func (m NetworkModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchNetwork(),
		m.tick(),
		m.timeout(),
	)
}

func (m NetworkModel) timeout() tea.Cmd {
	return tea.Tick(time.Second*10, func(t time.Time) tea.Msg {
		return networkTimeoutMsg(t)
	})
}

func (m NetworkModel) tick() tea.Cmd {
	return tea.Tick(time.Second*5, func(t time.Time) tea.Msg {
		return networkTickMsg(t)
	})
}

func (m NetworkModel) fetchNetwork() tea.Cmd {
	return func() tea.Msg {
		wg0Info := m.getInterfaceInfo("wg0")
		end0Info := m.getInterfaceInfo("end0")
		return networkMsg{
			wg0:  wg0Info,
			eth0: end0Info,
		}
	}
}

func (m NetworkModel) getInterfaceInfo(iface string) string {
	rates, err := services.GetInterfaceRates(iface)
	if err != nil {
		return "Interface not found"
	}

	stats, err := services.GetInterfaceStats(iface)
	if err != nil {
		return "Interface not found"
	}

	return fmt.Sprintf("RX: %s  TX: %s\nRate: ↓ %s  ↑ %s\nPackets: ↓ %d  ↑ %d\nErrors: ↓ %d  ↑ %d",
		services.FormatBytes(stats.RxBytes),
		services.FormatBytes(stats.TxBytes),
		services.FormatRate(rates.RxRate),
		services.FormatRate(rates.TxRate),
		stats.RxPackets,
		stats.TxPackets,
		stats.RxErrors,
		stats.TxErrors,
	)
}

func (m NetworkModel) Update(msg tea.Msg) (NetworkModel, tea.Cmd) {
	switch msg := msg.(type) {
	case networkTickMsg:
		return m, tea.Batch(m.fetchNetwork(), m.tick())

	case networkMsg:
		m.wg0Info = msg.wg0
		m.eth0Info = msg.eth0
		m.initialized = true
		return m, nil

	case networkTimeoutMsg:
		if !m.initialized {
			m.wg0Info = "Network stats timeout"
			m.eth0Info = "Network stats timeout"
			m.initialized = true
		}
		return m, nil
	}

	return m, nil
}

func (m NetworkModel) View() string {
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("99")).
		Padding(0, 1)

	boxStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240")).
		Padding(1, 2).
		Width(60)

	if !m.initialized {
		return headerStyle.Render("Network Interfaces") + "\n\n" + boxStyle.Render("Loading...")
	}

	header := headerStyle.Render("Network Interfaces")

	wg0Content := lipgloss.NewStyle().Bold(true).Render("wg0 (VPN)") + "\n" + m.wg0Info
	wg0Box := boxStyle.Render(wg0Content)

	end0Content := lipgloss.NewStyle().Bold(true).Render("end0 (LAN)") + "\n" + m.eth0Info
	end0Box := boxStyle.Render(end0Content)

	helpStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Padding(1, 0, 0, 1)
	help := helpStyle.Render("Updates every 5 seconds")

	return header + "\n\n" + wg0Box + "\n" + end0Box + "\n" + help
}
