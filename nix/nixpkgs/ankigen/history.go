package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type HistoryRecord struct {
	ID        string         `json:"id"`
	Timestamp time.Time      `json:"timestamp"`
	Question  string         `json:"question"`
	Provider  string         `json:"provider"`
	Flags     HistoryFlags   `json:"flags"`
	Events    []HistoryEvent `json:"events"`
	Result    HistoryResult  `json:"result"`
}

type HistoryFlags struct {
	Fast           bool    `json:"fast"`
	Web            bool    `json:"web"`
	Exa            bool    `json:"exa"`
	MaxTries       int     `json:"maxTries"`
	MaxSearches    int     `json:"maxSearches"`
	FocusThreshold float64 `json:"focusThreshold"`
	MaxTokens      int     `json:"maxTokens"`
}

type HistoryEvent struct {
	Type      string          `json:"type"`
	Timestamp time.Time       `json:"timestamp"`
	Data      json.RawMessage `json:"data"`
}

type HistoryResult struct {
	Cards         []Card `json:"cards"`
	Refused       bool   `json:"refused,omitempty"`
	RefusalReason string `json:"refusalReason,omitempty"`
	Error         string `json:"error,omitempty"`
}

func historyDir() string {
	home, _ := os.UserHomeDir()
	dir := filepath.Join(home, ".ankigen", "history")
	_ = os.MkdirAll(dir, 0o755)
	return dir
}

func newHistoryRecord(q, prov string) *HistoryRecord {
	now := time.Now()
	return &HistoryRecord{
		ID:        now.Format("2006-01-02T15-04-05"),
		Timestamp: now,
		Question:  q,
		Provider:  prov,
		Flags: HistoryFlags{
			Fast:           !deepThink,
			Web:            webMode,
			Exa:            useExa,
			MaxTries:       maxTries,
			MaxSearches:    maxSearches,
			FocusThreshold: focusThreshold,
			MaxTokens:      maxTokens,
		},
	}
}

func (h *HistoryRecord) AddEvent(eventType string, data any) {
	if h == nil {
		return
	}
	raw, _ := json.Marshal(data)
	h.Events = append(h.Events, HistoryEvent{
		Type:      eventType,
		Timestamp: time.Now(),
		Data:      raw,
	})
}

func (h *HistoryRecord) SetResult(ctx *PipelineContext) {
	if h == nil {
		return
	}
	h.Result = HistoryResult{
		Cards:         ctx.CardHistory,
		Refused:       ctx.Refused,
		RefusalReason: ctx.RefusalReason,
	}
	if ctx.Error != nil {
		h.Result.Error = ctx.Error.Error()
	}
}

func (h *HistoryRecord) Save() error {
	if h == nil {
		return nil
	}
	data, err := json.MarshalIndent(h, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(historyDir(), h.ID+".json"), data, 0o644)
}

func loadHistoryIndex() ([]HistoryRecord, error) {
	dir := historyDir()
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	var records []HistoryRecord
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			continue
		}
		var r HistoryRecord
		if err := json.Unmarshal(data, &r); err != nil {
			continue
		}
		r.Events = nil
		records = append(records, r)
	}

	sort.Slice(records, func(i, j int) bool {
		return records[i].Timestamp.After(records[j].Timestamp)
	})

	return records, nil
}

func loadHistoryRecord(id string) (*HistoryRecord, error) {
	data, err := os.ReadFile(filepath.Join(historyDir(), id+".json"))
	if err != nil {
		return nil, err
	}
	var r HistoryRecord
	if err := json.Unmarshal(data, &r); err != nil {
		return nil, err
	}
	return &r, nil
}

func historyToContext(record *HistoryRecord) *PipelineContext {
	ctx := &PipelineContext{
		Question:      record.Question,
		CardHistory:   record.Result.Cards,
		Refused:       record.Result.Refused,
		RefusalReason: record.Result.RefusalReason,
	}

	if len(ctx.CardHistory) > 0 {
		ctx.HistoryIndex = len(ctx.CardHistory) - 1
		ctx.Card = ctx.CardHistory[ctx.HistoryIndex]
	}

	for _, ev := range record.Events {
		switch ev.Type {
		case "search_terms":
			var data struct {
				Terms []string `json:"terms"`
			}
			if json.Unmarshal(ev.Data, &data) == nil {
				ctx.SearchTerms = data.Terms
			}
		case "web_search":
			var data struct {
				Results string `json:"results"`
			}
			if json.Unmarshal(ev.Data, &data) == nil {
				ctx.SearchResult = data.Results
			}
		case "summary":
			var data struct {
				Summary string `json:"summary"`
			}
			if json.Unmarshal(ev.Data, &data) == nil {
				ctx.Summary = data.Summary
			}
		case "add_input":
			var data struct {
				Inputs []string `json:"inputs"`
			}
			if json.Unmarshal(ev.Data, &data) == nil {
				ctx.AdditionalContext = data.Inputs
			}
		case "agent_turn":
			var data struct {
				Turn        int    `json:"turn"`
				Prompt      string `json:"prompt"`
				RawResponse string `json:"rawResponse"`
				Action      string `json:"action"`
				SearchTerm  string `json:"searchTerm,omitempty"`
				Error       string `json:"error,omitempty"`
			}
			if json.Unmarshal(ev.Data, &data) == nil {
				debug := DebugTurn{
					Turn:        data.Turn,
					Prompt:      data.Prompt,
					RawResponse: data.RawResponse,
				}
				if data.Action != "" {
					debug.Parsed = &AgentResponse{Action: data.Action, SearchTerm: data.SearchTerm}
				}
				if data.Error != "" {
					debug.Error = fmt.Errorf("%s", data.Error)
				}
				ctx.DebugHistory = append(ctx.DebugHistory, debug)
				ctx.AgentTurn = data.Turn
			}
		}
	}

	if record.Result.Error != "" {
		ctx.Error = fmt.Errorf("%s", record.Result.Error)
	}

	return ctx
}

func saveHistory(ctx *PipelineContext) {
	ctx.History.SetResult(ctx)
	_ = ctx.History.Save()
}

func recordStageEvent(ctx *PipelineContext, stage Stage) {
	if ctx.History == nil {
		return
	}
	switch stage.(type) {
	case searchTermsStage:
		ctx.History.AddEvent("search_terms", map[string]any{"terms": ctx.SearchTerms})
	case semanticSearchStage:
		ctx.History.AddEvent("web_search", map[string]any{"results": ctx.SearchResult})
	case summariseStage:
		ctx.History.AddEvent("summary", map[string]any{"summary": ctx.Summary})
	}
}

func recordAgentTurn(ctx *PipelineContext, msg agentTurnMsg) {
	if ctx.History == nil || len(ctx.DebugHistory) == 0 {
		return
	}
	last := ctx.DebugHistory[len(ctx.DebugHistory)-1]
	data := map[string]any{
		"turn":        msg.turn,
		"prompt":      last.Prompt,
		"rawResponse": last.RawResponse,
		"action":      msg.action,
	}
	if msg.err != nil {
		data["error"] = msg.err.Error()
	}
	if last.Parsed != nil {
		if last.Parsed.SearchTerm != "" {
			data["searchTerm"] = last.Parsed.SearchTerm
		}
		if last.Parsed.Card != nil {
			data["card"] = last.Parsed.Card
		}
	}
	ctx.History.AddEvent("agent_turn", data)
}

// --- History TUI ---

type historyItem struct {
	record HistoryRecord
}

func (i historyItem) Title() string {
	q := i.record.Question
	if len(q) > 60 {
		q = q[:57] + "..."
	}
	return q
}

func (i historyItem) Description() string {
	desc := i.record.Timestamp.Format("2006-01-02 15:04")
	desc += fmt.Sprintf(" \u2022 %s", i.record.Provider)
	if i.record.Result.Refused {
		desc += " \u2022 refused"
	} else if i.record.Result.Error != "" {
		desc += " \u2022 error"
	} else {
		desc += fmt.Sprintf(" \u2022 %d cards", len(i.record.Result.Cards))
	}
	return desc
}

func (i historyItem) FilterValue() string {
	return i.record.Question
}

type historyModel struct {
	list     list.Model
	selected *HistoryRecord
	quitting bool
}

func newHistoryModel(records []HistoryRecord) historyModel {
	items := make([]list.Item, len(records))
	for i, r := range records {
		items[i] = historyItem{record: r}
	}

	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = delegate.Styles.SelectedTitle.Foreground(nord8)
	delegate.Styles.SelectedDesc = delegate.Styles.SelectedDesc.Foreground(nord4)

	l := list.New(items, delegate, 80, 20)
	l.Title = "Restore from history"
	l.Styles.Title = lipgloss.NewStyle().Bold(true).Foreground(nord8).MarginLeft(2)
	l.SetFilteringEnabled(true)

	return historyModel{list: l}
}

func (m historyModel) Init() tea.Cmd {
	return nil
}

func (m historyModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetWidth(msg.Width)
		m.list.SetHeight(msg.Height)
		return m, nil
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			m.quitting = true
			return m, tea.Quit
		}
		if m.list.FilterState() != list.Filtering {
			switch msg.String() {
			case "q":
				m.quitting = true
				return m, tea.Quit
			case "enter":
				if item, ok := m.list.SelectedItem().(historyItem); ok {
					rec := item.record
					m.selected = &rec
				}
				return m, tea.Quit
			}
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

func (m historyModel) View() string {
	if m.quitting {
		return ""
	}
	return m.list.View()
}
