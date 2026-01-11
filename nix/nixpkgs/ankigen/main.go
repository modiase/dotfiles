package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/atotto/clipboard"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
)

var (
	exaAPIKey   string
	fastMode    bool
	localSearch bool
	maxTokens   int
	maxTries    int
	noCache     bool
	provider    string
	question    string
	rawOutput   bool
	webMode     bool
)

const (
	claudeHaiku = "claude-haiku-4-5-20251001"
	claudeOpus  = "claude-opus-4-5-20251101"

	geminiFlash = "gemini-2.5-flash"
	geminiPro   = "gemini-2.5-pro"

	gpt4    = "gpt-4.1-2025-04-14"
	gptMini = "o4-mini-2025-04-16"

	ollamaURL = "http://localhost:11434"
	vllmURL   = "http://herakles.home:4000/v1"
)

var (
	localModel  string
	remoteURL   string
	remoteModel string
)

type Card struct {
	Front       string `json:"front"`
	Back        string `json:"back"`
	Error       string `json:"error,omitempty"`
	RawResponse string `json:"-"`
}

type Stage interface {
	Name() string
	Execute(ctx *PipelineContext) error
	Validate(ctx *PipelineContext) error
	Next() Stage
}

// --- Stage 1: Search Terms ---

type searchTermsStage struct{}

func (searchTermsStage) Name() string { return "Generating search terms" }
func (searchTermsStage) Next() Stage  { return webSearchStage{} }

func (searchTermsStage) Execute(ctx *PipelineContext) error {
	terms, err := generateSearchTerms(ctx.Question)
	if err != nil {
		return err
	}
	ctx.SearchTerms = terms
	return nil
}

func (searchTermsStage) Validate(ctx *PipelineContext) error {
	if len(ctx.SearchTerms) == 0 {
		return fmt.Errorf("no search terms generated")
	}
	return nil
}

// --- Stage 2: Web Search ---

type webSearchStage struct{}

func (webSearchStage) Name() string { return "Searching web" }
func (webSearchStage) Next() Stage  { return summariseStage{} }

func (webSearchStage) Execute(ctx *PipelineContext) error {
	result, err := performWebSearch(ctx.SearchTerms)
	if err != nil {
		return err
	}
	ctx.SearchResult = result
	return nil
}

func (webSearchStage) Validate(ctx *PipelineContext) error {
	if strings.TrimSpace(ctx.SearchResult) == "" {
		return fmt.Errorf("no search results found")
	}
	return nil
}

// --- Stage 3: Summarise ---

type summariseStage struct{}

func (summariseStage) Name() string { return "Summarising results" }
func (summariseStage) Next() Stage  { return generateStage{} }

func (summariseStage) Execute(ctx *PipelineContext) error {
	summary, err := summariseResults(ctx.Question, ctx.SearchResult)
	if err != nil {
		return err
	}
	ctx.Summary = summary
	return nil
}

func (summariseStage) Validate(ctx *PipelineContext) error {
	if strings.TrimSpace(ctx.Summary) == "" {
		return fmt.Errorf("summary is empty")
	}
	return nil
}

// --- Stage 4: Generate Card ---

type generateStage struct{}

func (generateStage) Name() string { return "Generating card" }
func (generateStage) Next() Stage  { return nil }

func (generateStage) Execute(ctx *PipelineContext) error {
	ctx.FailedAttempts = nil
	for attempt := 1; attempt <= maxTries; attempt++ {
		card, err := generateCard(ctx.Question, ctx.Summary)
		if err != nil {
			ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Attempt %d error: %v", attempt, err))
			continue
		}
		if card.Error != "" || strings.TrimSpace(card.Front) == "" || strings.TrimSpace(card.Back) == "" {
			ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Attempt %d:\n%s", attempt, card.RawResponse))
			continue
		}
		ctx.Card = card
		return nil
	}
	return fmt.Errorf("card generation failed after %d attempts", maxTries)
}

func (generateStage) Validate(ctx *PipelineContext) error {
	if ctx.Card.Error != "" {
		return fmt.Errorf("card generation failed: %s", ctx.Card.Error)
	}
	if strings.TrimSpace(ctx.Card.Front) == "" || strings.TrimSpace(ctx.Card.Back) == "" {
		return fmt.Errorf("card has empty front or back")
	}
	return nil
}

type PipelineContext struct {
	Question       string
	SearchTerms    []string
	SearchResult   string
	Summary        string
	Card           Card
	Error          error
	FailedAttempts []string
	CardHistory    []Card
	HistoryIndex   int
}

type model struct {
	spinner     spinner.Model
	stage       Stage
	done        bool
	err         error
	substage    string
	context     *PipelineContext
	width       int
	height      int
	quitting    bool
	copied      bool
	tabView     *debugModel
	searchTotal int
	searchDone  int
	iterating   bool
	iterInput   textarea.Model
}

type debugModel struct {
	activeTab int // 0=Card, 1=SearchTerms, 2=SearchResults, 3=Summary
	viewport  viewport.Model
	contents  []string
	titles    []string
	width     int
	height    int
}

type inputModel struct {
	textarea textarea.Model
	done     bool
	question string
}

func initialInputModel() inputModel {
	ta := textarea.New()
	ta.Placeholder = "Enter your question..."
	ta.Focus()
	ta.SetWidth(80)
	ta.SetHeight(3)
	ta.ShowLineNumbers = false
	ta.CharLimit = 1000
	return inputModel{textarea: ta}
}

func (m inputModel) Init() tea.Cmd {
	return textarea.Blink
}

func (m inputModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			m.done = true
			return m, tea.Quit
		case "ctrl+d":
			m.question = strings.TrimSpace(m.textarea.Value())
			m.done = true
			return m, tea.Quit
		}
	case tea.WindowSizeMsg:
		m.textarea.SetWidth(min(msg.Width-4, 100))
	}

	var cmd tea.Cmd
	m.textarea, cmd = m.textarea.Update(msg)
	return m, cmd
}

func (m inputModel) View() string {
	return fmt.Sprintf(
		"\n%s\n\n%s\n\n%s\n",
		titleStyle.Render("Enter your question:"),
		m.textarea.View(),
		dimStyle.Render("Press Ctrl+D to submit, Esc to cancel"),
	)
}

type stageCompleteMsg struct {
	stage Stage
	ctx   *PipelineContext
}

type errorMsg struct {
	err error
}

type iterateCompleteMsg struct {
	card Card
	err  error
}

// Nord colour palette
const (
	nord4  = lipgloss.Color("#D8DEE9") // snow storm (dimmed text)
	nord8  = lipgloss.Color("#88C0D0") // frost cyan (primary)
	nord11 = lipgloss.Color("#BF616A") // aurora red (error)
	nord14 = lipgloss.Color("#A3BE8C") // aurora green (success)
)

var (
	titleStyle   = lipgloss.NewStyle().Bold(true).Foreground(nord8)
	boxStyle     = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(nord8).Padding(0, 1)
	labelStyle   = lipgloss.NewStyle().Bold(true).Foreground(nord8)
	dimStyle     = lipgloss.NewStyle().Foreground(nord4)
	errorStyle   = lipgloss.NewStyle().Foreground(nord11)
	successStyle = lipgloss.NewStyle().Foreground(nord14)
	helpStyle    = lipgloss.NewStyle().Foreground(nord4)
)

func initDebugModel(ctx *PipelineContext, width, height int) *debugModel {
	vpWidth, vpHeight := max(width-4, 40), max(height-8, 10)
	return &debugModel{
		viewport: viewport.New(vpWidth, vpHeight),
		titles:   []string{"Card", "Search Terms", "Search Results", "Summary"},
		contents: []string{"", formatSearchTerms(ctx.SearchTerms), ctx.SearchResult, ctx.Summary},
		width:    vpWidth,
		height:   vpHeight,
	}
}

func formatSearchTerms(terms []string) string {
	var b strings.Builder
	for i, term := range terms {
		b.WriteString(fmt.Sprintf("%d. %s\n", i+1, term))
	}
	return b.String()
}

func initialModel(question string) model {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(nord8)

	ta := textarea.New()
	ta.Placeholder = "Enter iteration instructions..."
	ta.SetWidth(70)
	ta.SetHeight(3)
	ta.ShowLineNumbers = false
	ta.CharLimit = 500

	return model{
		spinner:   s,
		stage:     searchTermsStage{},
		context:   &PipelineContext{Question: question},
		iterInput: ta,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		runStage(m.stage, m.context),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.iterating {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch msg.String() {
			case "esc":
				m.iterating = false
				m.iterInput.Reset()
				return m, nil
			case "ctrl+d":
				instructions := strings.TrimSpace(m.iterInput.Value())
				if instructions == "" {
					m.iterating = false
					return m, nil
				}
				m.iterating = false
				m.done = false
				m.substage = "iterating"
				m.iterInput.Reset()
				return m, runIterate(m.context, instructions)
			}
		}
		var cmd tea.Cmd
		m.iterInput, cmd = m.iterInput.Update(msg)
		return m, cmd
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			if m.done {
				m.quitting = true
				return m, tea.Quit
			}
		case "r":
			if m.done {
				m.stage = generateStage{}
				m.done = false
				m.copied = false
				m.substage = ""
				return m, runStage(m.stage, m.context)
			}
		case "i":
			if m.done && m.context.Card.Front != "" {
				m.iterating = true
				m.iterInput.Focus()
				return m, textarea.Blink
			}
		case "left", "h":
			if m.done && m.context.HistoryIndex > 0 {
				m.context.HistoryIndex--
				m.context.Card = m.context.CardHistory[m.context.HistoryIndex]
				m.copied = false
				m.substage = fmt.Sprintf("history %d/%d", m.context.HistoryIndex+1, len(m.context.CardHistory))
			}
		case "right", "l":
			if m.done && m.context.HistoryIndex < len(m.context.CardHistory)-1 {
				m.context.HistoryIndex++
				m.context.Card = m.context.CardHistory[m.context.HistoryIndex]
				m.copied = false
				m.substage = fmt.Sprintf("history %d/%d", m.context.HistoryIndex+1, len(m.context.CardHistory))
			}
		case "c":
			if m.done && m.context.Card.Front != "" {
				cardText := fmt.Sprintf("%s\t%s", m.context.Card.Front, m.context.Card.Back)
				if err := clipboard.WriteAll(cardText); err == nil {
					m.copied = true
					m.substage = "copied both"
				}
			}
		case "f":
			if m.done && m.context.Card.Front != "" {
				if err := clipboard.WriteAll(m.context.Card.Front); err == nil {
					m.copied = true
					m.substage = "copied front"
				}
			}
		case "b":
			if m.done && m.context.Card.Back != "" {
				if err := clipboard.WriteAll(m.context.Card.Back); err == nil {
					m.copied = true
					m.substage = "copied back"
				}
			}
		case "1", "2", "3", "4":
			if m.done && m.tabView != nil {
				tab := int(msg.String()[0] - '1')
				m.tabView.activeTab = tab
				if tab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[tab])
					m.tabView.viewport.GotoTop()
				}
			}
		case "tab":
			if m.done && m.tabView != nil {
				m.tabView.activeTab = (m.tabView.activeTab + 1) % 4
				if m.tabView.activeTab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[m.tabView.activeTab])
					m.tabView.viewport.GotoTop()
				}
			}
		case "shift+tab":
			if m.done && m.tabView != nil {
				m.tabView.activeTab = (m.tabView.activeTab + 3) % 4
				if m.tabView.activeTab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[m.tabView.activeTab])
					m.tabView.viewport.GotoTop()
				}
			}
		default:
			if m.done && m.tabView != nil && m.tabView.activeTab > 0 {
				var cmd tea.Cmd
				m.tabView.viewport, cmd = m.tabView.viewport.Update(msg)
				return m, cmd
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd

	case stageCompleteMsg:
		m.context = msg.ctx
		if _, ok := msg.stage.(searchTermsStage); ok {
			m.searchTotal = len(m.context.SearchTerms)
		}
		if _, ok := msg.stage.(webSearchStage); ok {
			m.searchDone = m.searchTotal
		}

		m.stage = msg.stage.Next()
		if m.stage == nil {
			m.done = true
			m.context.CardHistory = append(m.context.CardHistory, m.context.Card)
			m.context.HistoryIndex = len(m.context.CardHistory) - 1
			m.tabView = initDebugModel(m.context, m.width, m.height)
			return m, nil
		}
		return m, runStage(m.stage, m.context)

	case iterateCompleteMsg:
		if msg.err != nil {
			m.err = msg.err
			m.done = true
			return m, nil
		}
		m.context.Card = msg.card
		m.context.CardHistory = append(m.context.CardHistory, msg.card)
		m.context.HistoryIndex = len(m.context.CardHistory) - 1
		m.done = true
		m.substage = ""
		return m, nil

	case errorMsg:
		m.err = msg.err
		m.context.Error = msg.err
		return m, nil
	}

	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	if m.iterating {
		b.WriteString("\n")
		b.WriteString(titleStyle.Render("Iteration instructions:"))
		b.WriteString("\n\n")
		b.WriteString(m.iterInput.View())
		b.WriteString("\n\n")
		b.WriteString(dimStyle.Render("Ctrl+D to submit, Esc to cancel"))
		b.WriteString("\n")
		return b.String()
	}

	if m.err != nil {
		b.WriteString("\n")
		b.WriteString(errorStyle.Render("✗ Error: "))
		b.WriteString(errorStyle.Render(m.err.Error()))
		b.WriteString("\n\n")
		if len(m.context.FailedAttempts) > 0 {
			b.WriteString(titleStyle.Render("Failed attempts:"))
			b.WriteString("\n")
			b.WriteString(dimStyle.Render(strings.Repeat("─", 60)))
			b.WriteString("\n")
			for _, attempt := range m.context.FailedAttempts {
				b.WriteString(dimStyle.Render(attempt))
				b.WriteString("\n")
				b.WriteString(dimStyle.Render(strings.Repeat("─", 60)))
				b.WriteString("\n")
			}
		}
	} else if !m.done {
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" ")
		if m.substage == "iterating" {
			b.WriteString(titleStyle.Render("Iterating card"))
		} else {
			b.WriteString(titleStyle.Render(m.stage.Name()))
		}
		b.WriteString("...\n")

		switch m.stage.(type) {
		case webSearchStage:
			if m.searchTotal > 0 {
				b.WriteString(dimStyle.Render(fmt.Sprintf("  └─ %d/%d searches", m.searchDone, m.searchTotal)))
				b.WriteString("\n")
			}
		case summariseStage:
			if m.context.SearchResult != "" {
				b.WriteString(dimStyle.Render(fmt.Sprintf("  └─ %d chars of search results", len(m.context.SearchResult))))
				b.WriteString("\n")
			}
		case generateStage:
			if m.context.Summary != "" {
				b.WriteString(dimStyle.Render(fmt.Sprintf("  └─ %d chars of context", len(m.context.Summary))))
				b.WriteString("\n")
			}
		}

		completed := m.completedStages()
		for _, s := range completed {
			b.WriteString(successStyle.Render("✓"))
			b.WriteString(" ")
			switch s.(type) {
			case searchTermsStage:
				b.WriteString(dimStyle.Render(fmt.Sprintf("%s (%d terms)", s.Name(), len(m.context.SearchTerms))))
			case webSearchStage:
				b.WriteString(dimStyle.Render(fmt.Sprintf("%s (%d/%d)", s.Name(), m.searchDone, m.searchTotal)))
			case summariseStage:
				b.WriteString(dimStyle.Render(fmt.Sprintf("%s (%d chars)", s.Name(), len(m.context.Summary))))
			default:
				b.WriteString(dimStyle.Render(s.Name()))
			}
			b.WriteString("\n")
		}
	} else {
		width := m.width
		if width == 0 {
			width = 80
		}
		width = min(width-4, 100)

		b.WriteString("\n")

		if m.tabView != nil {
			var tabs strings.Builder
			for i, title := range m.tabView.titles {
				if i == m.tabView.activeTab {
					tabs.WriteString(titleStyle.Render(fmt.Sprintf("[%d] %s", i+1, title)))
				} else {
					tabs.WriteString(dimStyle.Render(fmt.Sprintf(" %d  %s", i+1, title)))
				}
				tabs.WriteString("  ")
			}
			b.WriteString(tabs.String())
			b.WriteString("\n")
			b.WriteString(dimStyle.Render(strings.Repeat("─", width)))
			b.WriteString("\n\n")
		}

		if m.tabView == nil || m.tabView.activeTab == 0 {
			b.WriteString(boxStyle.Width(width).Render(
				labelStyle.Render("FRONT") + "\n\n" + wordWrap(m.context.Card.Front, width-4),
			))
			b.WriteString("\n\n")
			b.WriteString(boxStyle.Width(width).Render(
				labelStyle.Render("BACK") + "\n\n" + wordWrap(m.context.Card.Back, width-4),
			))
			b.WriteString("\n\n")
			b.WriteString(dimStyle.Render(strings.Repeat("─", width)))
			b.WriteString("\n")

			if m.copied || (m.substage != "" && strings.HasPrefix(m.substage, "history")) {
				b.WriteString(successStyle.Render("✓ " + m.substage))
			} else {
				historyHint := ""
				if len(m.context.CardHistory) > 1 {
					historyHint = fmt.Sprintf("  [←→] History (%d/%d)", m.context.HistoryIndex+1, len(m.context.CardHistory))
				}
				b.WriteString(helpStyle.Render("[r] Regen  [i] Iterate  [c] Copy  [f] Front  [b] Back  [q] Quit" + historyHint))
			}
			b.WriteString("\n")
		} else {
			b.WriteString(titleStyle.Render(fmt.Sprintf("%s (%d%%)",
				m.tabView.titles[m.tabView.activeTab],
				int(m.tabView.viewport.ScrollPercent()*100))))
			b.WriteString("\n\n")
			b.WriteString(m.tabView.viewport.View())
			b.WriteString("\n")
			b.WriteString(helpStyle.Render("↑↓/j/k: scroll  [1] Back to Card  [q] Quit"))
			b.WriteString("\n")
		}
	}

	return b.String()
}

func runStage(stage Stage, ctx *PipelineContext) tea.Cmd {
	return func() tea.Msg {
		if err := stage.Execute(ctx); err != nil {
			return errorMsg{err: err}
		}
		if err := stage.Validate(ctx); err != nil {
			return errorMsg{err: err}
		}
		return stageCompleteMsg{stage: stage, ctx: ctx}
	}
}

func runIterate(ctx *PipelineContext, instructions string) tea.Cmd {
	return func() tea.Msg {
		card, err := iterateCard(ctx, instructions)
		return iterateCompleteMsg{card: card, err: err}
	}
}

func iterateCard(ctx *PipelineContext, instructions string) (Card, error) {
	systemPrompt, err := fetchSystemPrompt()
	if err != nil {
		return Card{}, err
	}

	var userPrompt strings.Builder
	userPrompt.WriteString(fmt.Sprintf("Original question: %s\n\n", ctx.Question))
	if ctx.Summary != "" {
		userPrompt.WriteString(fmt.Sprintf("Research context:\n%s\n\n", ctx.Summary))
	}
	userPrompt.WriteString(fmt.Sprintf("Current card:\nFront: %s\nBack: %s\n\n", ctx.Card.Front, ctx.Card.Back))
	userPrompt.WriteString(fmt.Sprintf("Please modify this card according to these instructions: %s", instructions))

	response, err := callLLMWithSystem(systemPrompt, userPrompt.String(), fastMode)
	if err != nil {
		return Card{}, err
	}

	var card Card
	card.RawResponse = response
	response = strings.TrimSpace(response)
	if start, end := strings.Index(response, "{"), strings.LastIndex(response, "}"); start != -1 && end > start {
		if err := json.Unmarshal([]byte(response[start:end+1]), &card); err == nil {
			card.RawResponse = response
			return card, nil
		}
	}

	return Card{Error: "Failed to parse iterated card", RawResponse: response}, nil
}

func (m model) completedStages() []Stage {
	var stages []Stage
	switch m.stage.(type) {
	case webSearchStage:
		stages = []Stage{searchTermsStage{}}
	case summariseStage:
		stages = []Stage{searchTermsStage{}, webSearchStage{}}
	case generateStage:
		stages = []Stage{searchTermsStage{}, webSearchStage{}, summariseStage{}}
	}
	return stages
}

func generateSearchTerms(question string) ([]string, error) {
	prompt := fmt.Sprintf(`Generate 1-5 web search queries to find accurate information for answering this question. Return ONLY a JSON array of strings, nothing else.

Question: %s

Example output: ["query 1", "query 2", "query 3"]`, question)

	response, err := callLLM(prompt, true)
	if err != nil {
		return nil, fmt.Errorf("search term generation failed: %w", err)
	}

	var terms []string
	response = strings.TrimSpace(response)
	if start, end := strings.Index(response, "["), strings.LastIndex(response, "]"); start != -1 && end > start {
		response = response[start : end+1]
	}

	if err := json.Unmarshal([]byte(response), &terms); err != nil || len(terms) == 0 {
		return []string{question}, nil
	}
	return terms, nil
}

func performWebSearch(terms []string) (string, error) {
	if localSearch {
		return performDuckDuckGoSearch(terms)
	}

	if exaAPIKey == "" {
		exaAPIKey = os.Getenv("EXA_API_KEY")
	}
	if exaAPIKey == "" {
		cmd := exec.Command("secrets", "get", "EXA_API_KEY")
		output, err := cmd.Output()
		if err == nil {
			exaAPIKey = strings.TrimSpace(string(output))
		}
	}

	if exaAPIKey == "" {
		return "", fmt.Errorf("EXA_API_KEY not found")
	}

	var results strings.Builder

	for _, term := range terms {
		result, err := searchExa(term)
		if err != nil {
			continue
		}
		results.WriteString(result)
		results.WriteString("\n---\n")
	}

	if results.Len() == 0 {
		return "", fmt.Errorf("all web searches failed")
	}

	return results.String(), nil
}

func performDuckDuckGoSearch(terms []string) (string, error) {
	var results strings.Builder

	for _, term := range terms {
		result, err := searchDuckDuckGo(term)
		if err != nil {
			continue
		}
		results.WriteString(result)
		results.WriteString("\n---\n")
	}

	if results.Len() == 0 {
		return "", fmt.Errorf("all web searches failed")
	}

	return results.String(), nil
}

func searchDuckDuckGo(query string) (string, error) {
	req, err := http.NewRequest("POST", "https://html.duckduckgo.com/html/",
		strings.NewReader("q="+strings.ReplaceAll(query, " ", "+")))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	return extractDuckDuckGoResults(string(body)), nil
}

func extractDuckDuckGoResults(html string) string {
	var results strings.Builder
	count := 0

	for _, line := range strings.Split(html, "\n") {
		if count >= 5 {
			break
		}
		if strings.Contains(line, "result__snippet") {
			if snippet := extractText(line); snippet != "" {
				results.WriteString(fmt.Sprintf("- %s\n\n", snippet))
				count++
			}
		}
	}

	return results.String()
}

func extractText(html string) string {
	result := html
	for strings.Contains(result, "<") {
		start := strings.Index(result, "<")
		end := strings.Index(result, ">")
		if start != -1 && end != -1 && end > start {
			result = result[:start] + result[end+1:]
		} else {
			break
		}
	}
	result = strings.ReplaceAll(result, "&amp;", "&")
	result = strings.ReplaceAll(result, "&lt;", "<")
	result = strings.ReplaceAll(result, "&gt;", ">")
	result = strings.ReplaceAll(result, "&quot;", "\"")
	result = strings.ReplaceAll(result, "&#x27;", "'")
	result = strings.ReplaceAll(result, "&nbsp;", " ")
	return strings.TrimSpace(result)
}

func searchExa(query string) (string, error) {
	payload := map[string]any{
		"query":      query,
		"numResults": 3,
		"contents": map[string]any{
			"text": map[string]int{"maxCharacters": 1000},
		},
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", "https://api.exa.ai/search", bytes.NewReader(body))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", exaAPIKey)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("exa API error: %s", string(respBody))
	}

	var result struct {
		Results []struct {
			Title string `json:"title"`
			URL   string `json:"url"`
			Text  string `json:"text"`
		} `json:"results"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	var sb strings.Builder
	for _, r := range result.Results {
		sb.WriteString(fmt.Sprintf("## %s\n%s\n\n", r.Title, r.Text))
	}

	return sb.String(), nil
}

func summariseResults(question, results string) (string, error) {
	prompt := fmt.Sprintf(`Summarise these search results to help answer the following question. Keep only the most relevant information.

Question: %s

Search Results:
%s

Provide a concise summary (300-500 words) of the key information relevant to answering the question.`, question, results)

	return callLLM(prompt, true)
}

func generateCard(question, context string) (Card, error) {
	systemPrompt, err := fetchSystemPrompt()
	if err != nil {
		return Card{}, err
	}

	userPrompt := fmt.Sprintf("Question: %s", question)
	if context != "" {
		userPrompt += fmt.Sprintf("\n\nContext from web research:\n%s", context)
	}

	response, err := callLLMWithSystem(systemPrompt, userPrompt, fastMode)
	if err != nil {
		return Card{}, err
	}

	var card Card
	card.RawResponse = response
	response = strings.TrimSpace(response)
	if start, end := strings.Index(response, "{"), strings.LastIndex(response, "}"); start != -1 && end > start {
		if err := json.Unmarshal([]byte(response[start:end+1]), &card); err == nil {
			card.RawResponse = response
			return card, nil
		}
	}

	lines := strings.Split(response, "\n")
	var front, back strings.Builder
	inBack := false

	for _, line := range lines {
		lower := strings.ToLower(line)
		if strings.Contains(lower, "front:") || strings.Contains(lower, "**front**") {
			continue
		}
		if strings.Contains(lower, "back:") || strings.Contains(lower, "**back**") {
			inBack = true
			continue
		}
		if inBack {
			back.WriteString(line)
			back.WriteString("\n")
		} else {
			front.WriteString(line)
			front.WriteString("\n")
		}
	}

	if front.Len() > 0 && back.Len() > 0 {
		return Card{
			Front:       strings.TrimSpace(front.String()),
			Back:        strings.TrimSpace(back.String()),
			RawResponse: response,
		}, nil
	}

	return Card{
		Error:       "Failed to parse response",
		RawResponse: response,
	}, nil
}

func fetchSystemPrompt() (string, error) {
	url := "https://gist.githubusercontent.com/modiase/88cbb2e7947a4ae970a91d9e335ab59c/raw/anki.txt"
	if noCache {
		url = fmt.Sprintf("%s?t=%d", url, time.Now().Unix())
	}

	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	prompt := string(body) + `

IMPORTANT:
1. Place all drafts and working inside <drafts></drafts> tags.
2. Return your final response as valid JSON with this exact format:
{"front": "question text here", "back": "answer text here"}

Do not include any other text outside the drafts tags and JSON object.`

	return prompt, nil
}

func callLLM(prompt string, useFast bool) (string, error) {
	return callLLMWithSystem("", prompt, useFast)
}

func callLLMWithSystem(systemPrompt, userPrompt string, useFast bool) (string, error) {
	switch provider {
	case "local":
		return callLocal(systemPrompt, userPrompt, useFast)
	case "herakles":
		return callRemote(systemPrompt, userPrompt, useFast)
	case "claude":
		return callClaude(systemPrompt, userPrompt, useFast)
	case "chatgpt":
		return callOpenAI(systemPrompt, userPrompt, useFast)
	case "gemini":
		return callGemini(systemPrompt, userPrompt, useFast)
	default:
		return callLocal(systemPrompt, userPrompt, useFast)
	}
}

func getAPIKey(name string) (string, error) {
	if key := os.Getenv(name); key != "" {
		return key, nil
	}
	cmd := exec.Command("secrets", "get", name)
	output, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("%s not found: %w", name, err)
	}
	return strings.TrimSpace(string(output)), nil
}

func callClaude(systemPrompt, userPrompt string, useFast bool) (string, error) {
	apiKey, err := getAPIKey("ANTHROPIC_API_KEY")
	if err != nil {
		return "", err
	}

	model := claudeOpus
	if useFast {
		model = claudeHaiku
	}

	payload := map[string]any{
		"model":       model,
		"max_tokens":  maxTokens,
		"temperature": 0.3,
		"messages": []map[string]string{
			{"role": "user", "content": userPrompt},
		},
	}

	if systemPrompt != "" {
		payload["system"] = systemPrompt
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", "https://api.anthropic.com/v1/messages", bytes.NewReader(body))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("x-api-key", apiKey)
	req.Header.Set("anthropic-version", "2023-06-01")

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("claude API error: %s", string(respBody))
	}

	var result struct {
		Content []struct {
			Text string `json:"text"`
		} `json:"content"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	if len(result.Content) == 0 {
		return "", fmt.Errorf("no content in response")
	}

	return stripTags(result.Content[0].Text, "drafts"), nil
}

func callOpenAI(systemPrompt, userPrompt string, useFast bool) (string, error) {
	apiKey, err := getAPIKey("OPENAI_API_KEY")
	if err != nil {
		return "", err
	}

	model := gpt4
	if useFast {
		model = gptMini
	}

	var input []map[string]any
	if systemPrompt != "" {
		input = append(input, map[string]any{
			"role":    "system",
			"content": []map[string]string{{"type": "input_text", "text": systemPrompt}},
		})
	}
	input = append(input, map[string]any{
		"role":    "user",
		"content": []map[string]string{{"type": "input_text", "text": userPrompt}},
	})

	payload := map[string]any{
		"model":             model,
		"max_output_tokens": maxTokens,
		"input":             input,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", "https://api.openai.com/v1/responses", bytes.NewReader(body))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("openai API error: %s", string(respBody))
	}

	var result struct {
		OutputText string `json:"output_text"`
		Output     []struct {
			Type    string `json:"type"`
			Content []struct {
				Type string `json:"type"`
				Text string `json:"text"`
			} `json:"content"`
		} `json:"output"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	if result.OutputText != "" {
		return stripTags(result.OutputText, "drafts"), nil
	}

	for _, out := range result.Output {
		if out.Type == "message" {
			for _, c := range out.Content {
				if c.Type == "output_text" && c.Text != "" {
					return stripTags(c.Text, "drafts"), nil
				}
			}
		}
	}

	return "", fmt.Errorf("no content in response")
}

func callGemini(systemPrompt, userPrompt string, useFast bool) (string, error) {
	apiKey, err := getAPIKey("GEMINI_API_KEY")
	if err != nil {
		return "", err
	}

	model := geminiPro
	if useFast {
		model = geminiFlash
	}

	payload := map[string]any{
		"contents": []map[string]any{
			{
				"role":  "user",
				"parts": []map[string]string{{"text": userPrompt}},
			},
		},
		"generationConfig": map[string]any{
			"maxOutputTokens": maxTokens,
			"temperature":     0.3,
		},
	}

	if systemPrompt != "" {
		payload["system_instruction"] = map[string]any{
			"parts": []map[string]string{{"text": systemPrompt}},
		}
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	url := fmt.Sprintf("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", model, apiKey)
	req, err := http.NewRequest("POST", url, bytes.NewReader(body))
	if err != nil {
		return "", err
	}

	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 120 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("gemini API error: %s", string(respBody))
	}

	var result struct {
		Candidates []struct {
			Content struct {
				Parts []struct {
					Text string `json:"text"`
				} `json:"parts"`
			} `json:"content"`
		} `json:"candidates"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	if len(result.Candidates) == 0 {
		return "", fmt.Errorf("no candidates in response")
	}

	var texts []string
	for _, c := range result.Candidates {
		for _, p := range c.Content.Parts {
			if p.Text != "" {
				texts = append(texts, p.Text)
			}
		}
	}

	return stripTags(strings.Join(texts, "\n\n"), "drafts"), nil
}

func detectLocalModel() error {
	if localModel != "" {
		return nil
	}

	resp, err := http.Get(ollamaURL + "/api/tags")
	if err != nil {
		return fmt.Errorf("local LLM unavailable: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	var result struct {
		Models []struct {
			Name string `json:"name"`
		} `json:"models"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return err
	}

	if len(result.Models) == 0 {
		return fmt.Errorf("no models available on local server")
	}

	localModel = result.Models[0].Name
	return nil
}

func callLocal(systemPrompt, userPrompt string, _ bool) (string, error) {
	if err := detectLocalModel(); err != nil {
		return "", err
	}

	userPrompt = "/no_think " + userPrompt

	var messages []map[string]string
	if systemPrompt != "" {
		messages = append(messages, map[string]string{"role": "system", "content": systemPrompt})
	}
	messages = append(messages, map[string]string{"role": "user", "content": userPrompt})

	payload := map[string]any{
		"model":    localModel,
		"messages": messages,
		"stream":   false,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", ollamaURL+"/api/chat", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 300 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("local LLM unavailable: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("local LLM error: %s", string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	if len(result.Choices) == 0 {
		return "", fmt.Errorf("no choices in response")
	}

	return stripTags(result.Choices[0].Message.Content, "think", "drafts"), nil
}

func detectHeraklesLLMServer() error {
	if remoteURL != "" {
		return nil
	}

	client := &http.Client{Timeout: 3 * time.Second}
	resp, err := client.Get(vllmURL + "/models")
	if err != nil {
		return fmt.Errorf("herakles LLM server unavailable at %s: %w", vllmURL, err)
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == 200 {
		remoteURL = vllmURL
		return nil
	}

	return fmt.Errorf("herakles LLM server unavailable: status %d from %s", resp.StatusCode, vllmURL)
}

func detectHeraklesLLMServerModel() error {
	if remoteModel != "" {
		return nil
	}

	if err := detectHeraklesLLMServer(); err != nil {
		return err
	}

	resp, err := http.Get(remoteURL + "/models")
	if err != nil {
		return fmt.Errorf("herakles LLM server unavailable: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	var result struct {
		Data []struct {
			ID string `json:"id"`
		} `json:"data"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return err
	}

	if len(result.Data) == 0 {
		return fmt.Errorf("no models available on herakles LLM server")
	}

	remoteModel = result.Data[0].ID
	return nil
}

func callRemote(systemPrompt, userPrompt string, _ bool) (string, error) {
	if err := detectHeraklesLLMServerModel(); err != nil {
		return "", err
	}

	userPrompt = "/no_think " + userPrompt

	var messages []map[string]string
	if systemPrompt != "" {
		messages = append(messages, map[string]string{"role": "system", "content": systemPrompt})
	}
	messages = append(messages, map[string]string{"role": "user", "content": userPrompt})

	payload := map[string]any{
		"model":    remoteModel,
		"messages": messages,
		"stream":   false,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	req, err := http.NewRequest("POST", remoteURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 300 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("remote LLM unavailable: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("remote LLM error: %s", string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return "", err
	}

	if len(result.Choices) == 0 {
		return "", fmt.Errorf("no choices in response")
	}

	return stripTags(result.Choices[0].Message.Content, "think", "drafts"), nil
}

func isHeraklesLLMServerAvailable() bool {
	return detectHeraklesLLMServer() == nil
}

func stripTags(s string, tags ...string) string {
	for _, tag := range tags {
		open, close := "<"+tag+">", "</"+tag+">"
		for {
			start := strings.Index(s, open)
			if start == -1 {
				break
			}
			end := strings.Index(s, close)
			if end == -1 {
				break
			}
			s = s[:start] + s[end+len(close):]
		}
	}
	return strings.TrimSpace(s)
}

func wordWrap(text string, width int) string {
	if width <= 0 {
		return text
	}

	var result strings.Builder
	lines := strings.Split(text, "\n")

	for i, line := range lines {
		if i > 0 {
			result.WriteString("\n")
		}

		words := strings.Fields(line)
		if len(words) == 0 {
			continue
		}

		lineLen := 0
		for j, word := range words {
			wordLen := len(word)
			if j > 0 && lineLen+1+wordLen > width {
				result.WriteString("\n")
				lineLen = 0
			} else if j > 0 {
				result.WriteString(" ")
				lineLen++
			}
			result.WriteString(word)
			lineLen += wordLen
		}
	}

	return result.String()
}

func main() {
	rootCmd := &cobra.Command{
		Use:   "ankigen [provider] [question]",
		Short: "Generate Anki flashcards using AI",
		Long: `Generate Anki flashcards using AI models with web search.

Providers: herakles (default), local, claude, chatgpt, gemini

Examples:
  ankigen "What is Docker?"
  ankigen herakles "What is Docker?"
  ankigen claude -f "Quick question"
  ankigen --no-web "Simple definition"`,
		Args: cobra.ArbitraryArgs,
		Run:  run,
	}

	var noWeb bool
	var useExa bool
	rootCmd.Flags().BoolVarP(&fastMode, "fast", "f", false, "Use faster/cheaper model")
	rootCmd.Flags().BoolVar(&noWeb, "no-web", false, "Disable web search pipeline")
	rootCmd.Flags().BoolVar(&useExa, "exa", false, "Use Exa API for search (default: DuckDuckGo)")
	rootCmd.Flags().BoolVarP(&noCache, "no-cache", "b", false, "Bypass system prompt cache")
	rootCmd.Flags().BoolVarP(&rawOutput, "raw", "r", false, "Output raw response")
	rootCmd.Flags().IntVarP(&maxTokens, "tokens", "t", 2000, "Max tokens")
	rootCmd.Flags().IntVarP(&maxTries, "max-tries", "m", 3, "Max generation attempts on parse failure")

	rootCmd.PreRun = func(cmd *cobra.Command, args []string) {
		webMode = !noWeb
		localSearch = !useExa
	}

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func isLocalAvailable() bool {
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get(ollamaURL + "/api/tags")
	if err != nil {
		return false
	}
	defer func() { _ = resp.Body.Close() }()
	return resp.StatusCode == 200
}

func run(cmd *cobra.Command, args []string) {
	providers := map[string]bool{"local": true, "herakles": true, "claude": true, "chatgpt": true, "gemini": true}

	if len(args) > 0 && providers[args[0]] {
		provider = args[0]
		args = args[1:]
	} else if isHeraklesLLMServerAvailable() {
		provider = "herakles"
	} else if isLocalAvailable() {
		provider = "local"
	} else {
		provider = "claude"
	}

	if len(args) == 0 {
		p := tea.NewProgram(initialInputModel())
		m, err := p.Run()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

		inputM := m.(inputModel)
		if inputM.question == "" {
			os.Exit(0)
		}
		question = inputM.question
	} else {
		question = strings.Join(args, " ")
	}

	if rawOutput {
		ctx := &PipelineContext{Question: question}

		var err error
		if webMode {
			ctx.SearchTerms, err = generateSearchTerms(ctx.Question)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}

			ctx.SearchResult, err = performWebSearch(ctx.SearchTerms)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}

			ctx.Summary, err = summariseResults(ctx.Question, ctx.SearchResult)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
		}

		ctx.Card, err = generateCard(ctx.Question, ctx.Summary)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}

		output, _ := json.MarshalIndent(ctx.Card, "", "  ")
		fmt.Println(string(output))
		return
	}

	if !webMode {
		card, err := generateCard(question, "")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Println()
		fmt.Println(boxStyle.Width(80).Render(
			labelStyle.Render("FRONT") + "\n\n" + card.Front,
		))
		fmt.Println()
		fmt.Println(boxStyle.Width(80).Render(
			labelStyle.Render("BACK") + "\n\n" + card.Back,
		))
		return
	}

	p := tea.NewProgram(initialModel(question), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
