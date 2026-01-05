package components

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/moye/hekate-dashboard/services"
)

var (
	healthTitleStyle = lipgloss.NewStyle().
				Bold(true).
				Foreground(lipgloss.Color("99")).
				Padding(0, 0, 1, 0)

	healthLabelStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("240"))

	healthBorderStyle = lipgloss.NewStyle().
				Border(lipgloss.RoundedBorder()).
				BorderForeground(lipgloss.Color("99")).
				Padding(1, 2)
)

type HealthModel struct {
	health     *services.HealthInfo
	err        error
	lastUpdate time.Time
	width      int
	height     int
}

type healthTickMsg time.Time
type healthErrorMsg struct{ err error }

func (e healthErrorMsg) Error() string { return e.err.Error() }

func NewHealthModel() HealthModel {
	return HealthModel{}
}

func (m HealthModel) Init() tea.Cmd {
	return tea.Batch(
		m.fetchHealthInfo(),
		healthTickCmd(),
	)
}

func (m HealthModel) Update(msg tea.Msg) (HealthModel, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case healthTickMsg:
		return m, tea.Batch(
			m.fetchHealthInfo(),
			healthTickCmd(),
		)

	case services.HealthInfo:
		m.health = &msg
		m.err = nil
		m.lastUpdate = time.Now()

	case healthErrorMsg:
		m.err = msg.err
	}

	return m, nil
}

func (m HealthModel) View() string {
	if m.err != nil {
		errorStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Padding(1, 2)
		return errorStyle.Render(fmt.Sprintf("Error: %v", m.err))
	}

	if m.health == nil {
		loadingStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Padding(1, 2)
		return loadingStyle.Render("Loading system health...")
	}

	// CPU panel
	cpuPanel := m.renderCPU()

	// Memory panel
	memPanel := m.renderMemory()

	// System panel
	sysPanel := m.renderSystem()

	topRow := lipgloss.JoinHorizontal(lipgloss.Top, cpuPanel, "  ", memPanel)
	return lipgloss.JoinVertical(lipgloss.Left, topRow, "", sysPanel)
}

func (m HealthModel) renderCPU() string {
	borderStyle := healthBorderStyle.Copy().
		Width(32).
		Height(9)

	// Color based on CPU usage
	usageStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	if m.health.CPU.UsagePercent > 80 {
		usageStyle = usageStyle.Foreground(lipgloss.Color("9"))
	} else if m.health.CPU.UsagePercent > 50 {
		usageStyle = usageStyle.Foreground(lipgloss.Color("11"))
	}

	content := healthTitleStyle.Render("CPU") + "\n"
	content += healthLabelStyle.Render("Usage: ") + usageStyle.Render(fmt.Sprintf("%d%%", m.health.CPU.UsagePercent)) + "\n"
	content += m.renderBar(m.health.CPU.UsagePercent, 20)

	return borderStyle.Render(content)
}

func (m HealthModel) renderMemory() string {
	borderStyle := healthBorderStyle.Copy().
		Width(32).
		Height(9)

	// Color based on memory usage
	usageStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	if m.health.Memory.UsagePercent > 80 {
		usageStyle = usageStyle.Foreground(lipgloss.Color("9"))
	} else if m.health.Memory.UsagePercent > 50 {
		usageStyle = usageStyle.Foreground(lipgloss.Color("11"))
	}

	totalMB := float64(m.health.Memory.TotalKB) / 1024
	usedMB := float64(m.health.Memory.UsedKB) / 1024
	availMB := float64(m.health.Memory.AvailableKB) / 1024

	content := healthTitleStyle.Render("Memory") + "\n"
	content += healthLabelStyle.Render("Total: ") + fmt.Sprintf("%.0f MB\n", totalMB)
	content += healthLabelStyle.Render("Used:  ") + usageStyle.Render(fmt.Sprintf("%.0f MB (%d%%)", usedMB, m.health.Memory.UsagePercent)) + "\n"
	content += healthLabelStyle.Render("Avail: ") + fmt.Sprintf("%.0f MB\n", availMB)
	content += m.renderBar(m.health.Memory.UsagePercent, 25)

	return borderStyle.Render(content)
}

func (m HealthModel) renderSystem() string {
	borderStyle := healthBorderStyle.Copy().Width(68)

	labelStyle := healthLabelStyle.Copy().Width(12)
	valueStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("255"))

	uptime := formatUptime(m.health.System.UptimeSeconds)

	tempStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("10"))
	if m.health.System.TemperatureCelsius > 70 {
		tempStyle = tempStyle.Foreground(lipgloss.Color("9"))
	} else if m.health.System.TemperatureCelsius > 60 {
		tempStyle = tempStyle.Foreground(lipgloss.Color("11"))
	}

	content := healthTitleStyle.Render("System") + "\n"
	content += labelStyle.Render("Uptime:") + valueStyle.Render(uptime) + "\n"
	content += labelStyle.Render("Load Avg:") + valueStyle.Render(fmt.Sprintf("%s, %s, %s",
		m.health.System.LoadAvg1Min,
		m.health.System.LoadAvg5Min,
		m.health.System.LoadAvg15Min)) + "\n"
	if m.health.System.TemperatureCelsius > 0 {
		content += labelStyle.Render("Temperature:") + tempStyle.Render(fmt.Sprintf("%d°C", m.health.System.TemperatureCelsius))
	}

	return borderStyle.Render(content)
}

func (m HealthModel) renderBar(percent int, width int) string {
	filled := percent * width / 100
	if filled > width {
		filled = width
	}

	bar := ""
	for i := 0; i < width; i++ {
		if i < filled {
			if percent > 80 {
				bar += lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render("█")
			} else if percent > 50 {
				bar += lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render("█")
			} else {
				bar += lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Render("█")
			}
		} else {
			bar += lipgloss.NewStyle().Foreground(lipgloss.Color("240")).Render("░")
		}
	}

	return bar
}

func (m HealthModel) fetchHealthInfo() tea.Cmd {
	return func() tea.Msg {
		health, err := services.GetHealthInfo()
		if err != nil {
			return healthErrorMsg{err}
		}
		return *health
	}
}

func healthTickCmd() tea.Cmd {
	return tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
		return healthTickMsg(t)
	})
}

func formatUptime(seconds int) string {
	days := seconds / 86400
	hours := (seconds % 86400) / 3600
	minutes := (seconds % 3600) / 60

	if days > 0 {
		return fmt.Sprintf("%dd %dh %dm", days, hours, minutes)
	}
	if hours > 0 {
		return fmt.Sprintf("%dh %dm", hours, minutes)
	}
	return fmt.Sprintf("%dm", minutes)
}
