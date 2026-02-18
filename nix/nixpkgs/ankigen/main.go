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
	"sync"
	"time"

	"github.com/atotto/clipboard"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/spf13/cobra"
	"semsearch/semsearch"
)

var (
	exaAPIKey      string
	fastMode       bool
	focusThreshold float64
	maxSearches    int
	maxTokens      int
	maxTries       int
	noCache        bool
	provider       string
	question       string
	rawOutput      bool
	useExa         bool
	webMode        bool
)

const (
	claudeHaiku = "claude-haiku-4-5-20251001"
	claudeOpus  = "claude-opus-4-6"

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

type AgentResponse struct {
	Action     string `json:"action"`
	Reason     string `json:"reason,omitempty"`
	Question   string `json:"question,omitempty"`
	SearchTerm string `json:"search_term,omitempty"`
	Card       *Card  `json:"card,omitempty"`
}

type DebugTurn struct {
	Turn        int
	Prompt      string
	RawResponse string
	Parsed      *AgentResponse
	Error       error
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
func (searchTermsStage) Next() Stage  { return semanticSearchStage{} }

func (searchTermsStage) Execute(ctx *PipelineContext) error {
	ctx.Logf("Generating search terms for: %s", ctx.Question)
	terms, err := generateSearchTerms(ctx.Question)
	if err != nil {
		ctx.Logf("Error: %v", err)
		return err
	}
	ctx.Logf("Generated %d search terms", len(terms))
	ctx.SearchTerms = terms
	return nil
}

func (searchTermsStage) Validate(ctx *PipelineContext) error {
	if len(ctx.SearchTerms) == 0 {
		return fmt.Errorf("no search terms generated")
	}
	return nil
}

// --- Stage 2: Semantic Search ---

type semanticSearchStage struct{}

func (semanticSearchStage) Name() string { return "Semantic search" }
func (semanticSearchStage) Next() Stage  { return summariseStage{} }

func (semanticSearchStage) Execute(ctx *PipelineContext) error {
	if useExa {
		return performExaSearch(ctx)
	}
	return performSemanticGoogleSearch(ctx)
}

func (semanticSearchStage) Validate(ctx *PipelineContext) error {
	if strings.TrimSpace(ctx.SearchResult) == "" {
		return fmt.Errorf("no search results found")
	}
	return nil
}

func performExaSearch(ctx *PipelineContext) error {
	ctx.Logf("Searching with Exa (%d terms)", len(ctx.SearchTerms))
	result, err := performWebSearch(ctx.SearchTerms)
	if err != nil {
		ctx.Logf("Error: %v", err)
		return err
	}
	ctx.Logf("Received %d bytes of search results", len(result))
	ctx.SearchResult = result
	return nil
}

func performSemanticGoogleSearch(ctx *PipelineContext) error {
	allTerms := ctx.SearchTerms

	cfg := semsearch.Config{
		GoogleAPIKey: getEnvOrSecret("SEMSEARCH_GOOGLE_API_KEY", "custom-search-api-key"),
		GoogleCX:     getEnvOrSecret("SEMSEARCH_GOOGLE_CX", "custom-search-api-id"),
		EmbedURL:     vllmURL,
		EmbedModel:   "qwen-embed",
		Threshold:    focusThreshold,
		NumResults:   5,
	}

	if semsearch.IsEmbedServerAvailable(cfg) {
		creativeTerms, err := generateCreativeSearchTerms(ctx.Question)
		if err != nil {
			ctx.Logf("Creative term generation failed: %v", err)
		} else if len(creativeTerms) > 0 {
			ctx.Logf("Generated %d creative search terms", len(creativeTerms))
			allTerms = append(allTerms, creativeTerms...)
		}
	}

	ctx.Logf("Searching Google with %d terms", len(allTerms))
	result, err := semsearch.SearchRaw(allTerms, cfg)
	if err != nil {
		ctx.Logf("Error: %v", err)
		return err
	}
	ctx.Logf("Received %d bytes of search results", len(result))
	ctx.SearchResult = result

	if !semsearch.IsEmbedServerAvailable(cfg) {
		ctx.Logf("Skipping semantic filtering (embed server unavailable)")
		return nil
	}

	ctx.Logf("Filtering results with threshold %.2f", focusThreshold)
	focused, err := semsearch.FilterRaw(ctx.Question, ctx.SearchResult, cfg, pipelineLogger{ctx})
	if err != nil {
		ctx.Logf("Filtering failed, using original results: %v", err)
		return nil
	}
	ctx.SearchResult = focused
	return nil
}

type pipelineLogger struct {
	ctx *PipelineContext
}

func (l pipelineLogger) Logf(format string, args ...any) {
	l.ctx.Logf(format, args...)
}

// --- Stage 3: Summarise ---

type summariseStage struct{}

func (summariseStage) Name() string { return "Summarising results" }
func (summariseStage) Next() Stage  { return generateStage{} }

func (summariseStage) Execute(ctx *PipelineContext) error {
	ctx.Logf("Summarising %d bytes of search results", len(ctx.SearchResult))
	summary, err := summariseResults(ctx.Question, ctx.SearchResult)
	if err != nil {
		ctx.Logf("Error: %v", err)
		return err
	}
	ctx.Logf("Generated %d byte summary", len(summary))
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
	ctx.Logf("Starting agentic card generation from %d byte summary", len(ctx.Summary))
	ctx.FailedAttempts = nil
	ctx.AgentTurn = 0
	return nil
}

func runAgentTurn(ctx *PipelineContext) tea.Cmd {
	return func() tea.Msg {
		ctx.AgentTurn++
		if ctx.AgentTurn > maxTries {
			ctx.Logf("Turn limit reached (%d turns), stopping", maxTries)
			ctx.DebugHistory = append(ctx.DebugHistory, DebugTurn{
				Turn:  ctx.AgentTurn,
				Error: fmt.Errorf("turn limit reached (%d max)", maxTries),
			})
			return agentTurnMsg{
				turn: ctx.AgentTurn,
				done: true,
				err:  fmt.Errorf("card generation failed after %d agent turns (see Debug tab)", maxTries),
				ctx:  ctx,
			}
		}

		ctx.Logf("Agent turn %d/%d (searches used: %d)", ctx.AgentTurn, maxTries, ctx.SearchCount)

		resp, debug, err := callAgenticLLM(ctx, ctx.AgentTurn)
		ctx.DebugHistory = append(ctx.DebugHistory, debug)
		if err != nil {
			ctx.Logf("Agent turn %d failed: %v", ctx.AgentTurn, err)
			ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Turn %d error: %v", ctx.AgentTurn, err))
			return agentTurnMsg{turn: ctx.AgentTurn, action: "error", detail: err.Error(), ctx: ctx}
		}

		ctx.Logf("Agent action: %s", resp.Action)

		switch resp.Action {
		case "generate":
			if resp.Card == nil || strings.TrimSpace(resp.Card.Front) == "" || strings.TrimSpace(resp.Card.Back) == "" {
				ctx.Logf("Turn %d: invalid card in generate response", ctx.AgentTurn)
				ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Turn %d: invalid card", ctx.AgentTurn))
				return agentTurnMsg{turn: ctx.AgentTurn, action: "invalid", detail: "empty card", ctx: ctx}
			}
			ctx.Logf("Card generated successfully")
			ctx.Card = *resp.Card
			return agentTurnMsg{turn: ctx.AgentTurn, action: "generate", done: true, ctx: ctx}

		case "refuse":
			ctx.Logf("Agent refused: %s", resp.Reason)
			ctx.Refused = true
			ctx.RefusalReason = resp.Reason
			return agentTurnMsg{turn: ctx.AgentTurn, action: "refuse", detail: resp.Reason, done: true, ctx: ctx}

		case "search":
			if maxSearches != -1 && ctx.SearchCount >= maxSearches {
				ctx.Logf("Search limit reached (%d), re-prompting agent", maxSearches)
				ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Turn %d: search rejected (limit reached)", ctx.AgentTurn))
				return agentTurnMsg{turn: ctx.AgentTurn, action: "limit", detail: "search limit reached", ctx: ctx}
			}
			ctx.SearchCount++
			ctx.Logf("Agent requested search: %s", resp.SearchTerm)
			result, searchErr := performAdditionalSearch(resp.SearchTerm)
			if searchErr != nil {
				ctx.Logf("Search failed: %v", searchErr)
				ctx.Summary += fmt.Sprintf("\n\n[Search for '%s' failed: %v]", resp.SearchTerm, searchErr)
			} else {
				ctx.Logf("Search returned %d bytes", len(result))
				ctx.Summary += fmt.Sprintf("\n\n[Additional search: %s]\n%s", resp.SearchTerm, result)
			}
			return agentTurnMsg{turn: ctx.AgentTurn, action: "search", detail: resp.SearchTerm, ctx: ctx}

		case "ask":
			ctx.Logf("Agent asking user: %s", resp.Question)
			ctx.AgentQuestion = resp.Question
			ctx.AwaitingInput = true
			return agentTurnMsg{turn: ctx.AgentTurn, action: "ask", detail: resp.Question, done: true, ctx: ctx}

		default:
			ctx.Logf("Turn %d: unknown action '%s'", ctx.AgentTurn, resp.Action)
			ctx.FailedAttempts = append(ctx.FailedAttempts, fmt.Sprintf("Turn %d: unknown action '%s'", ctx.AgentTurn, resp.Action))
			return agentTurnMsg{turn: ctx.AgentTurn, action: "unknown", detail: resp.Action, ctx: ctx}
		}
	}
}

func (generateStage) Validate(ctx *PipelineContext) error {
	if ctx.AgentTurn == 0 || ctx.Refused || ctx.AwaitingInput {
		return nil
	}
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
	Logs           strings.Builder
	SearchCount    int
	Refused        bool
	RefusalReason  string
	AgentQuestion  string
	UserResponses  []string
	AwaitingInput  bool
	DebugHistory   []DebugTurn
	AgentTurn      int
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
	agentAsking bool
	agentInput  textarea.Model
}

type debugModel struct {
	activeTab int // 0=Card, 1=SearchTerms, 2=SearchResults, 3=Summary, 4=Logs, 5=Debug
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

type agentTurnMsg struct {
	turn   int
	action string
	detail string
	done   bool
	err    error
	ctx    *PipelineContext
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
		titles:   []string{"Card", "Search Terms", "Search Results", "Summary", "Logs", "Debug"},
		contents: []string{"", formatSearchTerms(ctx.SearchTerms), ctx.SearchResult, ctx.Summary, ctx.Logs.String(), formatDebugHistory(ctx.DebugHistory)},
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

func formatDebugHistory(history []DebugTurn) string {
	if len(history) == 0 {
		return "(no agent turns recorded)"
	}
	var b strings.Builder
	for _, turn := range history {
		b.WriteString(fmt.Sprintf("═══ Turn %d ═══\n", turn.Turn))
		b.WriteString(fmt.Sprintf("PROMPT:\n%s\n\n", turn.Prompt))
		b.WriteString(fmt.Sprintf("RAW RESPONSE:\n%s\n\n", turn.RawResponse))
		if turn.Parsed != nil {
			b.WriteString(fmt.Sprintf("PARSED: action=%s", turn.Parsed.Action))
			switch turn.Parsed.Action {
			case "search":
				b.WriteString(fmt.Sprintf(", term=%q", turn.Parsed.SearchTerm))
			case "ask":
				b.WriteString(fmt.Sprintf(", question=%q", turn.Parsed.Question))
			case "refuse":
				b.WriteString(fmt.Sprintf(", reason=%q", turn.Parsed.Reason))
			}
			b.WriteString("\n")
		}
		if turn.Error != nil {
			b.WriteString(fmt.Sprintf("ERROR: %v\n", turn.Error))
		}
		b.WriteString("\n")
	}
	return b.String()
}

func (ctx *PipelineContext) Logf(format string, args ...any) {
	ctx.Logs.WriteString(fmt.Sprintf(format+"\n", args...))
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

	agentTa := textarea.New()
	agentTa.Placeholder = "Your response..."
	agentTa.SetWidth(70)
	agentTa.SetHeight(3)
	agentTa.ShowLineNumbers = false
	agentTa.CharLimit = 500

	return model{
		spinner:    s,
		stage:      searchTermsStage{},
		context:    &PipelineContext{Question: question},
		iterInput:  ta,
		agentInput: agentTa,
	}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(
		m.spinner.Tick,
		runStage(m.stage, m.context),
	)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.agentAsking {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch msg.String() {
			case "esc", "ctrl+c":
				m.agentAsking = false
				m.context.AwaitingInput = false
				m.done = true
				m.context.Refused = true
				m.context.RefusalReason = "User cancelled agent question"
				m.tabView = initDebugModel(m.context, m.width, m.height)
				m.agentInput.Reset()
				return m, nil
			case "ctrl+d":
				response := strings.TrimSpace(m.agentInput.Value())
				if response == "" {
					return m, nil
				}
				m.agentAsking = false
				m.context.AwaitingInput = false
				m.context.UserResponses = append(m.context.UserResponses, response)
				m.context.Logf("User responded: %s", response)
				m.done = false
				m.substage = fmt.Sprintf("Turn %d: continuing...", m.context.AgentTurn+1)
				m.agentInput.Reset()
				return m, runAgentTurn(m.context)
			}
		}
		var cmd tea.Cmd
		m.agentInput, cmd = m.agentInput.Update(msg)
		return m, cmd
	}

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
				return m, tea.Batch(runIterate(m.context, instructions), m.spinner.Tick)
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
				m.substage = "Turn 1: thinking..."
				m.context.Refused = false
				m.context.RefusalReason = ""
				m.context.AwaitingInput = false
				m.context.AgentQuestion = ""
				m.context.DebugHistory = nil
				m.context.AgentTurn = 0
				return m, runAgentTurn(m.context)
			}
		case "i":
			if m.done && m.context.Card.Front != "" {
				m.iterating = true
				m.iterInput.Focus()
				return m, textarea.Blink
			}
		case "h":
			if m.done && m.context.HistoryIndex > 0 {
				m.context.HistoryIndex--
				m.context.Card = m.context.CardHistory[m.context.HistoryIndex]
				m.copied = false
				m.substage = fmt.Sprintf("history %d/%d", m.context.HistoryIndex+1, len(m.context.CardHistory))
			}
		case "l":
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
		case "1", "2", "3", "4", "5":
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
				m.tabView.activeTab = (m.tabView.activeTab + 1) % 6
				if m.tabView.activeTab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[m.tabView.activeTab])
					m.tabView.viewport.GotoTop()
				}
			}
		case "shift+tab":
			if m.done && m.tabView != nil {
				m.tabView.activeTab = (m.tabView.activeTab + 5) % 6
				if m.tabView.activeTab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[m.tabView.activeTab])
					m.tabView.viewport.GotoTop()
				}
			}
		case "left":
			if m.done && m.tabView != nil {
				m.tabView.activeTab = (m.tabView.activeTab + 5) % 6
				if m.tabView.activeTab > 0 {
					m.tabView.viewport.SetContent(m.tabView.contents[m.tabView.activeTab])
					m.tabView.viewport.GotoTop()
				}
			}
		case "right":
			if m.done && m.tabView != nil {
				m.tabView.activeTab = (m.tabView.activeTab + 1) % 6
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
		if _, ok := msg.stage.(semanticSearchStage); ok {
			m.searchDone = m.searchTotal
		}

		if _, ok := msg.stage.(generateStage); ok {
			m.substage = "Turn 1: thinking..."
			return m, runAgentTurn(m.context)
		}

		m.stage = msg.stage.Next()
		if m.stage == nil {
			m.done = true
			if !m.context.Refused {
				m.context.CardHistory = append(m.context.CardHistory, m.context.Card)
				m.context.HistoryIndex = len(m.context.CardHistory) - 1
			}
			m.tabView = initDebugModel(m.context, m.width, m.height)
			return m, nil
		}
		return m, runStage(m.stage, m.context)

	case agentTurnMsg:
		m.context = msg.ctx
		if msg.err != nil {
			m.err = msg.err
			m.done = true
			m.tabView = initDebugModel(m.context, m.width, m.height)
			m.tabView.activeTab = 5
			m.tabView.viewport.SetContent(m.tabView.contents[5])
			return m, nil
		}

		switch msg.action {
		case "generate":
			m.substage = fmt.Sprintf("Turn %d: generated card", msg.turn)
			m.done = true
			m.context.CardHistory = append(m.context.CardHistory, m.context.Card)
			m.context.HistoryIndex = len(m.context.CardHistory) - 1
			m.tabView = initDebugModel(m.context, m.width, m.height)
			return m, nil

		case "refuse":
			m.substage = fmt.Sprintf("Turn %d: refused", msg.turn)
			m.done = true
			m.tabView = initDebugModel(m.context, m.width, m.height)
			return m, nil

		case "search":
			m.substage = fmt.Sprintf("Turn %d: searched %q", msg.turn, msg.detail)
			return m, runAgentTurn(m.context)

		case "ask":
			m.substage = fmt.Sprintf("Turn %d: asking question", msg.turn)
			m.agentAsking = true
			m.agentInput.Focus()
			return m, textarea.Blink

		default:
			m.substage = fmt.Sprintf("Turn %d: %s, retrying...", msg.turn, msg.action)
			return m, runAgentTurn(m.context)
		}

	case iterateCompleteMsg:
		if msg.err != nil {
			m.err = msg.err
			m.done = true
			m.tabView = initDebugModel(m.context, m.width, m.height)
			m.tabView.activeTab = 5
			m.tabView.viewport.SetContent(m.tabView.contents[5])
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
		m.done = true
		m.tabView = initDebugModel(m.context, m.width, m.height)
		m.tabView.activeTab = 5
		m.tabView.viewport.SetContent(m.tabView.contents[5])
		return m, nil
	}

	return m, nil
}

func (m model) View() string {
	if m.quitting {
		return ""
	}

	var b strings.Builder

	if m.agentAsking {
		b.WriteString("\n")
		b.WriteString(titleStyle.Render("Agent is asking:"))
		b.WriteString("\n\n")
		b.WriteString(boxStyle.Width(min(m.width-4, 80)).Render(m.context.AgentQuestion))
		b.WriteString("\n\n")
		b.WriteString(titleStyle.Render("Your response:"))
		b.WriteString("\n\n")
		b.WriteString(m.agentInput.View())
		b.WriteString("\n\n")
		b.WriteString(dimStyle.Render("Ctrl+D to submit, Esc to cancel"))
		b.WriteString("\n")
		return b.String()
	}

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

	if !m.done {
		b.WriteString("\n")
		b.WriteString(m.spinner.View())
		b.WriteString(" ")
		if m.substage == "iterating" {
			b.WriteString(titleStyle.Render("Iterating card"))
		} else {
			b.WriteString(titleStyle.Render(m.stage.Name()))
		}
		if m.substage != "" && m.substage != "iterating" {
			b.WriteString(" - ")
			b.WriteString(dimStyle.Render(m.substage))
		}
		b.WriteString("\n")

		switch m.stage.(type) {
		case semanticSearchStage:
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
			case semanticSearchStage:
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

		if m.err != nil {
			b.WriteString(errorStyle.Render("✗ Error: "))
			b.WriteString(errorStyle.Render(m.err.Error()))
			b.WriteString("\n\n")
		}

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
			if m.context.Refused {
				b.WriteString(boxStyle.Width(width).BorderForeground(nord11).Render(
					errorStyle.Render("AGENT REFUSED") + "\n\n" + wordWrap(m.context.RefusalReason, width-4),
				))
				b.WriteString("\n\n")
				b.WriteString(dimStyle.Render(strings.Repeat("─", width)))
				b.WriteString("\n")
				b.WriteString(helpStyle.Render("[r] Retry  [q] Quit  [2-5] View context"))
				b.WriteString("\n")
			} else {
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
			}
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
	case semanticSearchStage:
		stages = []Stage{searchTermsStage{}}
	case summariseStage:
		stages = []Stage{searchTermsStage{}, semanticSearchStage{}}
	case generateStage:
		stages = []Stage{searchTermsStage{}, semanticSearchStage{}, summariseStage{}}
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

func generateCreativeSearchTerms(question string) ([]string, error) {
	prompt := fmt.Sprintf(`Generate 2-3 creative, lateral-thinking web search queries to find unexpected but relevant information for this question. Think of related concepts, analogies, or alternative framings. Return ONLY a JSON array of strings.

Question: %s

Example: For "Why is the sky blue?" you might generate:
["Rayleigh scattering atmosphere", "wavelength light dispersion physics", "why sunset orange red"]`, question)

	payload := map[string]any{
		"model": remoteModel,
		"messages": []map[string]string{
			{"role": "user", "content": "/no_think " + prompt},
		},
		"temperature": 0.8,
		"stream":      false,
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest("POST", remoteURL+"/chat/completions", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 60 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("herakles error: %s", string(respBody))
	}

	var result struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, err
	}

	if len(result.Choices) == 0 {
		return nil, fmt.Errorf("no response from herakles")
	}

	response := strings.TrimSpace(result.Choices[0].Message.Content)
	if start, end := strings.Index(response, "["), strings.LastIndex(response, "]"); start != -1 && end > start {
		response = response[start : end+1]
	}

	var terms []string
	if err := json.Unmarshal([]byte(response), &terms); err != nil {
		return nil, err
	}
	return terms, nil
}

func performWebSearch(terms []string) (string, error) {
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

	type searchResult struct {
		result string
		err    error
	}

	resultsChan := make(chan searchResult, len(terms))
	var wg sync.WaitGroup

	for _, term := range terms {
		wg.Add(1)
		go func(t string) {
			defer wg.Done()
			result, err := searchExa(t)
			resultsChan <- searchResult{result: result, err: err}
		}(term)
	}

	go func() {
		wg.Wait()
		close(resultsChan)
	}()

	var results strings.Builder
	for r := range resultsChan {
		if r.err != nil {
			continue
		}
		results.WriteString(r.result)
		results.WriteString("\n---\n")
	}

	if results.Len() == 0 {
		return "", fmt.Errorf("all web searches failed")
	}

	return results.String(), nil
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

func callAgenticLLM(ctx *PipelineContext, turn int) (AgentResponse, DebugTurn, error) {
	debug := DebugTurn{Turn: turn}

	systemPrompt, err := fetchAgenticSystemPrompt(ctx)
	if err != nil {
		debug.Error = err
		return AgentResponse{}, debug, err
	}

	var userPrompt strings.Builder
	userPrompt.WriteString(fmt.Sprintf("Question: %s\n\n", ctx.Question))
	if ctx.Summary != "" {
		userPrompt.WriteString(fmt.Sprintf("Research context:\n%s\n\n", ctx.Summary))
	}
	if len(ctx.UserResponses) > 0 {
		userPrompt.WriteString("User responses to your questions:\n")
		for _, r := range ctx.UserResponses {
			userPrompt.WriteString(fmt.Sprintf("- %s\n", r))
		}
		userPrompt.WriteString("\n")
	}
	userPrompt.WriteString("Decide your next action.")
	debug.Prompt = userPrompt.String()

	response, err := callLLMWithSystem(systemPrompt, userPrompt.String(), fastMode)
	if err != nil {
		debug.Error = err
		return AgentResponse{}, debug, err
	}

	debug.RawResponse = response
	var resp AgentResponse
	response = strings.TrimSpace(response)
	if start, end := strings.Index(response, "{"), strings.LastIndex(response, "}"); start != -1 && end > start {
		if err := json.Unmarshal([]byte(response[start:end+1]), &resp); err == nil {
			debug.Parsed = &resp
			return resp, debug, nil
		}
	}

	parseErr := fmt.Errorf("failed to parse agent response: %s", response)
	debug.Error = parseErr
	return AgentResponse{}, debug, parseErr
}

func fetchAgenticSystemPrompt(ctx *PipelineContext) (string, error) {
	basePrompt, err := fetchSystemPrompt()
	if err != nil {
		return "", err
	}

	searchesRemaining := "unlimited"
	if maxSearches != -1 {
		remaining := maxSearches - ctx.SearchCount
		if remaining < 0 {
			remaining = 0
		}
		searchesRemaining = fmt.Sprintf("%d", remaining)
	}

	agentInstructions := fmt.Sprintf(`

You are an agentic card generator. You must respond with ONE of these JSON actions:

1. Generate a card (when you have enough information):
{"action": "generate", "card": {"front": "question text", "back": "answer text"}}

2. Refuse (when the request is impossible, nonsensical, or wrong):
{"action": "refuse", "reason": "explanation of why you cannot create a card"}

3. Search for more information (%s searches remaining):
{"action": "search", "search_term": "your search query"}

4. Ask the user for clarification:
{"action": "ask", "question": "your question to the user"}

IMPORTANT:
- You MUST respond with exactly one JSON object, no other text
- If you have enough context to make a good card, use "generate"
- If the question is unclear or ambiguous, use "ask"
- If you need more specific information, use "search"
- Only use "refuse" if the request fundamentally cannot be answered`, searchesRemaining)

	return basePrompt + agentInstructions, nil
}

func performAdditionalSearch(term string) (string, error) {
	cfg := semsearch.Config{
		GoogleAPIKey: getEnvOrSecret("SEMSEARCH_GOOGLE_API_KEY", "custom-search-api-key"),
		GoogleCX:     getEnvOrSecret("SEMSEARCH_GOOGLE_CX", "custom-search-api-id"),
		NumResults:   3,
	}

	result, err := semsearch.SearchRaw([]string{term}, cfg)
	if err != nil {
		return "", err
	}

	if len(result) > 2000 {
		result = result[:2000] + "\n[truncated]"
	}

	return result, nil
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

func getEnvOrSecret(envName, defaultSecret string) string {
	if val := os.Getenv(envName); val != "" {
		return val
	}
	secretName := os.Getenv(envName + "_SECRET_NAME")
	if secretName == "" {
		secretName = defaultSecret
	}
	if secretName == "" {
		return ""
	}
	out, err := exec.Command("secrets", "get", secretName, "--read-through").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
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

	client := &http.Client{Timeout: 300 * time.Second}
	var respBody []byte
	var lastErr error

	for attempt := range 3 {
		if attempt > 0 {
			time.Sleep(time.Duration(attempt*2) * time.Second)
		}

		req, err := http.NewRequest("POST", remoteURL+"/chat/completions", bytes.NewReader(body))
		if err != nil {
			return "", err
		}
		req.Header.Set("Content-Type", "application/json")

		resp, err := client.Do(req)
		if err != nil {
			lastErr = fmt.Errorf("remote LLM unavailable: %w", err)
			continue
		}

		respBody, err = io.ReadAll(resp.Body)
		_ = resp.Body.Close()
		if err != nil {
			lastErr = err
			continue
		}

		if resp.StatusCode == 200 {
			lastErr = nil
			break
		}

		lastErr = fmt.Errorf("remote LLM error: %s", string(respBody))
		if resp.StatusCode < 500 && !strings.Contains(string(respBody), "try again") {
			return "", lastErr
		}
	}

	if lastErr != nil {
		return "", lastErr
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
	rootCmd.Flags().BoolVarP(&fastMode, "fast", "f", false, "Use faster/cheaper model")
	rootCmd.Flags().BoolVar(&noWeb, "no-web", false, "Disable web search pipeline")
	rootCmd.Flags().BoolVar(&useExa, "exa", false, "Use Exa API for search (default: DuckDuckGo)")
	rootCmd.Flags().BoolVarP(&noCache, "no-cache", "b", false, "Bypass system prompt cache")
	rootCmd.Flags().BoolVarP(&rawOutput, "raw", "r", false, "Output raw response")
	rootCmd.Flags().IntVarP(&maxTokens, "tokens", "t", 2000, "Max tokens")
	rootCmd.Flags().IntVarP(&maxTries, "max-tries", "m", 3, "Max generation attempts on parse failure")
	rootCmd.Flags().IntVar(&maxSearches, "max-searches", 3, "Max additional searches agent can request (-1 = unlimited)")
	rootCmd.Flags().Float64Var(&focusThreshold, "focus-threshold", 0.7, "Minimum similarity for focused results (0-1)")

	rootCmd.PreRun = func(cmd *cobra.Command, args []string) {
		webMode = !noWeb
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
	} else if envProvider := os.Getenv("ANKIGEN_DEFAULT_PROVIDER"); envProvider != "" && providers[envProvider] {
		provider = envProvider
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
