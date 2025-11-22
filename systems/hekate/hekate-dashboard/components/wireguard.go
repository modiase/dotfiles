package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

var (
	wgTitleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("99")).
			Padding(0, 0, 1, 0)

	wgLabelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240"))

	wgValueStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("255"))

	wgBorderStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("99")).
			Padding(1, 2)
)

type WireGuardModel struct {
	info       *services.WireGuardInfo
	err        error
	lastUpdate time.Time
	width      int
	height     int
}

type wireguardTickMsg time.Time
type wireguardErrorMsg struct{ err error }

func (e wireguardErrorMsg) Error() string { return e.err.Error() }

func NewWireGuardModel() WireGuardModel {
	return WireGuardModel{}
}

func (m WireGuardModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchWireGuardInfo(),
		wireguardTickCmd(),
	)
}

func (m WireGuardModel) Update(msg tea.Msg) (WireGuardModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case wireguardTickMsg:
		return m, tea.Batch(
			m.fetchWireGuardInfo(),
			wireguardTickCmd(),
		)

	case services.WireGuardInfo:
		m.info = &msg
		m.err = nil
		m.lastUpdate = time.Now()

	case wireguardErrorMsg:
		m.err = msg.err
	}

	return m, nil
}

func (m WireGuardModel) View() string {
	if m.err != nil {
		errorStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Padding(1, 2)
		return errorStyle.Render(fmt.Sprintf("Error: %v", m.err))
	}

	if m.info == nil {
		loadingStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Padding(1, 2)
		return loadingStyle.Render("Loading WireGuard status...")
	}

	// Interface status panel
	interfacePanel := m.renderInterface()

	// Peers panel
	peersPanel := m.renderPeers()

	return lipgloss.JoinVertical(lipgloss.Left, interfacePanel, "", peersPanel)
}

func (m WireGuardModel) renderInterface() string {
	labelStyle := wgLabelStyle.Copy().Width(15)

	content := wgTitleStyle.Render("Interface Status") + "\n"
	content += labelStyle.Render("Interface:") + wgValueStyle.Render(m.info.Interface.Name) + "\n"
	content += labelStyle.Render("Public Key:") + wgValueStyle.Render(m.info.Interface.PublicKey) + "\n"
	content += labelStyle.Render("Listen Port:") + wgValueStyle.Render(fmt.Sprintf("%d", m.info.Interface.ListenPort))

	return wgBorderStyle.Render(content)
}

func (m WireGuardModel) renderPeers() string {
	labelStyle := wgLabelStyle.Copy().Width(20)

	connectedStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("10")).
		Bold(true)

	disconnectedStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("9"))

	content := wgTitleStyle.Render(fmt.Sprintf("Peers (%d)", len(m.info.Peers))) + "\n\n"

	if len(m.info.Peers) == 0 {
		content += lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Italic(true).
			Render("No peers configured")
		return wgBorderStyle.Render(content)
	}

	for i, peer := range m.info.Peers {
		if i > 0 {
			content += "\n" + wgLabelStyle.Render("─────────────────────────────────────────") + "\n"
		}

		peerName := "Unknown"
		if peer.AllowedIPs == "10.0.0.2/32" {
			peerName = "iris"
		} else if peer.AllowedIPs == "10.0.0.3/32" {
			peerName = "pegasus"
		}

		content += labelStyle.Render("Peer:") + wgValueStyle.Render(peerName) + "\n"
		content += labelStyle.Render("IP:") + wgValueStyle.Render(peer.AllowedIPs) + "\n"
		content += labelStyle.Render("Endpoint:") + wgValueStyle.Render(peer.Endpoint) + "\n"

		// Connection status based on handshake
		var status string
		var statusStyle lipgloss.Style
		if !peer.LatestHandshake.IsZero() {
			timeSince := time.Since(peer.LatestHandshake)
			if timeSince < 3*time.Minute {
				status = fmt.Sprintf("Connected (%s ago)", formatWGDuration(timeSince))
				statusStyle = connectedStyle
			} else {
				status = fmt.Sprintf("Stale (%s ago)", formatWGDuration(timeSince))
				statusStyle = disconnectedStyle
			}
		} else {
			status = "Never connected"
			statusStyle = disconnectedStyle
		}
		content += labelStyle.Render("Status:") + statusStyle.Render(status) + "\n"

		rxMB := float64(peer.TransferRx) / 1024 / 1024
		txMB := float64(peer.TransferTx) / 1024 / 1024
		content += labelStyle.Render("Transfer (RX/TX):") + wgValueStyle.Render(fmt.Sprintf("%.2f MB / %.2f MB", rxMB, txMB)) + "\n"

		if peer.PersistentKeepalive > 0 {
			content += labelStyle.Render("Keepalive:") + wgValueStyle.Render(fmt.Sprintf("%ds", peer.PersistentKeepalive))
		}
	}

	return wgBorderStyle.Render(content)
}

func (m WireGuardModel) fetchWireGuardInfo() tea.Cmd {
	return func() tea.Msg {
		info, err := services.GetWireGuardInfo()
		if err != nil {
			return wireguardErrorMsg{err}
		}
		return *info
	}
}

func wireguardTickCmd() tea.Cmd {
	return tea.Tick(2*time.Second, func(t time.Time) tea.Msg {
		return wireguardTickMsg(t)
	})
}

func formatWGDuration(d time.Duration) string {
	if d < time.Minute {
		return fmt.Sprintf("%ds", int(d.Seconds()))
	}
	if d < time.Hour {
		return fmt.Sprintf("%dm", int(d.Minutes()))
	}
	if d < 24*time.Hour {
		return fmt.Sprintf("%dh", int(d.Hours()))
	}
	return fmt.Sprintf("%dd", int(d.Hours()/24))
}
