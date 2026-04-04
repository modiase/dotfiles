package main

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/charmbracelet/bubbles/textarea"
	tea "github.com/charmbracelet/bubbletea"
)

func init() {
	saveHistoryFunc = func(*PipelineContext) {}
}

func newTestContext() *PipelineContext {
	return &PipelineContext{
		Question:    "What is Go?",
		Card:        Card{Front: "Q", Back: "A"},
		CardHistory: []Card{{Front: "Q", Back: "A"}},
		History:     newHistoryRecord("What is Go?", "test"),
	}
}

func newTestModel() model {
	ctx := newTestContext()
	ta := textarea.New()
	ta.SetWidth(70)
	ta.SetHeight(3)
	agentTa := textarea.New()
	agentTa.SetWidth(70)
	agentTa.SetHeight(3)
	return model{
		done:       true,
		context:    ctx,
		width:      80,
		height:     24,
		tabView:    initDebugModel(ctx, 80, 24),
		iterInput:  ta,
		agentInput: agentTa,
	}
}

func sendKey(m model, key string) (model, tea.Cmd) {
	msg := tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(key)}
	switch key {
	case "ctrl+c":
		msg = tea.KeyMsg{Type: tea.KeyCtrlC}
	case "ctrl+d":
		msg = tea.KeyMsg{Type: tea.KeyCtrlD}
	case "esc":
		msg = tea.KeyMsg{Type: tea.KeyEscape}
	case "enter":
		msg = tea.KeyMsg{Type: tea.KeyEnter}
	}
	return sendMsg(m, msg)
}

func sendMsg(m model, msg tea.Msg) (model, tea.Cmd) {
	result, cmd := m.Update(msg)
	return result.(model), cmd
}

// --- Bug 2: SearchCount not reset on regenerate ---

func TestRegenerate_ResetsSearchCount(t *testing.T) {
	m := newTestModel()
	m.context.SearchCount = 5
	m, _ = sendKey(m, "r")
	if m.context.SearchCount != 0 {
		t.Errorf("SearchCount = %d, want 0", m.context.SearchCount)
	}
}

func TestRegenerate_ResetsAllState(t *testing.T) {
	m := newTestModel()
	m.context.SearchCount = 5
	m.context.AgentTurn = 3
	m.context.DebugHistory = []DebugTurn{{Turn: 1}}
	m.context.Refused = true
	m.context.RefusalReason = "test"
	m.context.AwaitingInput = true
	m.context.AgentQuestion = "test?"
	m.context.FailedAttempts = []string{"fail"}

	m, _ = sendKey(m, "r")

	if m.context.SearchCount != 0 {
		t.Errorf("SearchCount = %d, want 0", m.context.SearchCount)
	}
	if m.context.AgentTurn != 0 {
		t.Errorf("AgentTurn = %d, want 0", m.context.AgentTurn)
	}
	if m.context.DebugHistory != nil {
		t.Errorf("DebugHistory = %v, want nil", m.context.DebugHistory)
	}
	if m.context.Refused {
		t.Error("Refused = true, want false")
	}
	if m.context.RefusalReason != "" {
		t.Errorf("RefusalReason = %q, want empty", m.context.RefusalReason)
	}
	if m.context.AwaitingInput {
		t.Error("AwaitingInput = true, want false")
	}
	if m.context.AgentQuestion != "" {
		t.Errorf("AgentQuestion = %q, want empty", m.context.AgentQuestion)
	}
	if m.context.FailedAttempts != nil {
		t.Errorf("FailedAttempts = %v, want nil", m.context.FailedAttempts)
	}
	if m.done {
		t.Error("done = true, want false")
	}
	if _, ok := m.stage.(generateStage); !ok {
		t.Errorf("stage = %T, want generateStage", m.stage)
	}
	if !strings.Contains(m.substage, "Turn 1") {
		t.Errorf("substage = %q, want to contain 'Turn 1'", m.substage)
	}
}

// --- Bug 1: Debug tab not reinitialised after iteration ---

func TestIterateComplete_Success_InitialisesDebugModel(t *testing.T) {
	m := newTestModel()
	m.tabView = nil
	m.done = false

	m, _ = sendMsg(m, iterateCompleteMsg{card: Card{Front: "Q2", Back: "A2"}})

	if m.tabView == nil {
		t.Error("tabView is nil, want initialised")
	}
	if !m.done {
		t.Error("done = false, want true")
	}
}

func TestIterateComplete_Success_PreservesDebugHistory(t *testing.T) {
	m := newTestModel()
	m.context.DebugHistory = []DebugTurn{
		{Turn: 1, Prompt: "p1"},
		{Turn: 2, Prompt: "p2"},
		{Turn: 3, Prompt: "p3"},
	}
	m.done = false

	m, _ = sendMsg(m, iterateCompleteMsg{card: Card{Front: "Q2", Back: "A2"}})

	if len(m.context.DebugHistory) != 3 {
		t.Errorf("DebugHistory len = %d, want 3", len(m.context.DebugHistory))
	}
}

// --- Bug 3: substage not updated after iteration ---

func TestIterateComplete_Success_UpdatesSubstage(t *testing.T) {
	m := newTestModel()
	m.substage = "iterating"
	m.done = false

	m, _ = sendMsg(m, iterateCompleteMsg{card: Card{Front: "Q2", Back: "A2"}})

	if m.substage != "iterated card" {
		t.Errorf("substage = %q, want %q", m.substage, "iterated card")
	}
}

func TestIterateComplete_Success_AppendsCardHistory(t *testing.T) {
	m := newTestModel()
	m.done = false
	newCard := Card{Front: "Q2", Back: "A2"}

	m, _ = sendMsg(m, iterateCompleteMsg{card: newCard})

	if len(m.context.CardHistory) != 2 {
		t.Errorf("CardHistory len = %d, want 2", len(m.context.CardHistory))
	}
	if m.context.HistoryIndex != 1 {
		t.Errorf("HistoryIndex = %d, want 1", m.context.HistoryIndex)
	}
	if m.context.Card != newCard {
		t.Errorf("Card = %+v, want %+v", m.context.Card, newCard)
	}
}

func TestIterateComplete_Error_InitialisesDebugModel(t *testing.T) {
	m := newTestModel()
	m.tabView = nil
	m.done = false

	m, _ = sendMsg(m, iterateCompleteMsg{err: errors.New("fail")})

	if m.tabView == nil {
		t.Fatal("tabView is nil, want initialised")
	}
	if m.tabView.activeTab != 6 {
		t.Errorf("activeTab = %d, want 6", m.tabView.activeTab)
	}
	if !m.done {
		t.Error("done = false, want true")
	}
}

// --- Bug 4: stripTags closing tag search position ---

func TestStripTags(t *testing.T) {
	tests := []struct {
		name  string
		input string
		tags  []string
		want  string
	}{
		{"basic", "<think>foo</think>bar", []string{"think"}, "bar"},
		{"multiple", "<think>a</think>mid<think>b</think>", []string{"think"}, "mid"},
		{"two tags", "<think>a</think><drafts>b</drafts>c", []string{"think", "drafts"}, "c"},
		{"no tags", "no tags here", []string{"think"}, "no tags here"},
		{"unclosed", "<think>unclosed", []string{"think"}, "<think>unclosed"},
		{"empty", "", []string{"think"}, ""},
		{"closing before opening", "</think>text<think>x</think>rest", []string{"think"}, "</think>textrest"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := stripTags(tt.input, tt.tags...)
			if got != tt.want {
				t.Errorf("stripTags(%q, %v) = %q, want %q", tt.input, tt.tags, got, tt.want)
			}
		})
	}
}

func TestStripTags_ClosingBeforeOpening(t *testing.T) {
	got := stripTags("</tag>hello<tag>world</tag>", "tag")
	if got != "</tag>hello" {
		t.Errorf("got %q, want %q", got, "</tag>hello")
	}
}

func TestStripTags_NoInfiniteLoop(t *testing.T) {
	done := make(chan string, 1)
	go func() {
		done <- stripTags("a</x><x>b</x>c", "x")
	}()
	select {
	case got := <-done:
		if got != "a</x>c" {
			t.Errorf("got %q, want %q", got, "a</x>c")
		}
	case <-time.After(2 * time.Second):
		t.Fatal("stripTags did not complete (possible infinite loop)")
	}
}

func TestStripCodeFences(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  string
	}{
		{"json", "```json\n{\"a\":\"b\"}\n```", "{\"a\":\"b\"}"},
		{"plain", "plain text", "plain text"},
		{"empty fences", "```\n```", ""},
		{"go", "```go\nfunc main(){}\n```", "func main(){}"},
		{"unclosed", "```\ncontent without closing", "content without closing"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := stripCodeFences(tt.input)
			if got != tt.want {
				t.Errorf("stripCodeFences(%q) = %q, want %q", tt.input, got, tt.want)
			}
		})
	}
}

// --- Model.Update message handler tests ---

func TestUpdate_AgentTurnMsg_Generate(t *testing.T) {
	m := newTestModel()
	m.done = false
	ctx := m.context
	ctx.Card = Card{Front: "Generated", Back: "Card"}

	m, _ = sendMsg(m, agentTurnMsg{action: "generate", turn: 3, ctx: ctx})

	if !m.done {
		t.Error("done = false, want true")
	}
	if m.tabView == nil {
		t.Error("tabView is nil")
	}
	if !strings.Contains(m.substage, "generated card") {
		t.Errorf("substage = %q, want to contain 'generated card'", m.substage)
	}
	if len(m.context.CardHistory) != 2 {
		t.Errorf("CardHistory len = %d, want 2", len(m.context.CardHistory))
	}
}

func TestUpdate_AgentTurnMsg_Refuse(t *testing.T) {
	m := newTestModel()
	m.done = false
	ctx := m.context
	ctx.Refused = true

	m, _ = sendMsg(m, agentTurnMsg{action: "refuse", turn: 2, ctx: ctx})

	if !m.done {
		t.Error("done = false, want true")
	}
	if m.tabView == nil {
		t.Error("tabView is nil")
	}
	if !strings.Contains(m.substage, "refused") {
		t.Errorf("substage = %q, want to contain 'refused'", m.substage)
	}
}

func TestUpdate_AgentTurnMsg_Search(t *testing.T) {
	m := newTestModel()
	m.done = false

	m, _ = sendMsg(m, agentTurnMsg{action: "search", turn: 1, detail: "quantum physics", ctx: m.context})

	if m.done {
		t.Error("done = true, want false")
	}
	if !strings.Contains(m.substage, "searched") {
		t.Errorf("substage = %q, want to contain 'searched'", m.substage)
	}
	if !strings.Contains(m.substage, "quantum physics") {
		t.Errorf("substage = %q, want to contain 'quantum physics'", m.substage)
	}
}

func TestUpdate_AgentTurnMsg_Ask(t *testing.T) {
	m := newTestModel()
	m.done = false

	m, _ = sendMsg(m, agentTurnMsg{action: "ask", turn: 2, ctx: m.context})

	if !m.agentAsking {
		t.Error("agentAsking = false, want true")
	}
	if !strings.Contains(m.substage, "asking question") {
		t.Errorf("substage = %q, want to contain 'asking question'", m.substage)
	}
}

func TestUpdate_AgentTurnMsg_Error(t *testing.T) {
	m := newTestModel()
	m.done = false

	m, _ = sendMsg(m, agentTurnMsg{err: errors.New("api error"), ctx: m.context})

	if !m.done {
		t.Error("done = false, want true")
	}
	if m.err == nil {
		t.Error("err is nil, want error")
	}
	if m.tabView == nil {
		t.Fatal("tabView is nil")
	}
	if m.tabView.activeTab != 6 {
		t.Errorf("activeTab = %d, want 6", m.tabView.activeTab)
	}
}

func TestUpdate_ErrorMsg(t *testing.T) {
	m := newTestModel()
	m.done = false

	m, _ = sendMsg(m, errorMsg{err: errors.New("fail")})

	if !m.done {
		t.Error("done = false, want true")
	}
	if m.err == nil {
		t.Error("err is nil, want error")
	}
	if m.tabView == nil {
		t.Fatal("tabView is nil")
	}
	if m.tabView.activeTab != 5 {
		t.Errorf("activeTab = %d, want 5", m.tabView.activeTab)
	}
}

func TestUpdate_StageCompleteMsg_Advances(t *testing.T) {
	m := newTestModel()
	m.done = false
	m.stage = searchTermsStage{}
	m.context.SearchTerms = []string{"term1", "term2"}

	m, _ = sendMsg(m, stageCompleteMsg{stage: searchTermsStage{}, ctx: m.context})

	if _, ok := m.stage.(semanticSearchStage); !ok {
		t.Errorf("stage = %T, want semanticSearchStage", m.stage)
	}
}

func TestUpdate_StageCompleteMsg_GenerateStartsAgent(t *testing.T) {
	m := newTestModel()
	m.done = false

	m, cmd := sendMsg(m, stageCompleteMsg{stage: generateStage{}, ctx: m.context})

	if m.substage != "Turn 1: thinking..." {
		t.Errorf("substage = %q, want %q", m.substage, "Turn 1: thinking...")
	}
	if cmd == nil {
		t.Error("cmd is nil, want runAgentTurn command")
	}
}

func TestUpdate_KeyPress_HistoryNavigation(t *testing.T) {
	m := newTestModel()
	m.context.CardHistory = []Card{
		{Front: "Q0", Back: "A0"},
		{Front: "Q1", Back: "A1"},
		{Front: "Q2", Back: "A2"},
	}
	m.context.HistoryIndex = 2
	m.context.Card = m.context.CardHistory[2]

	m, _ = sendKey(m, "h")
	if m.context.HistoryIndex != 1 {
		t.Errorf("after h: HistoryIndex = %d, want 1", m.context.HistoryIndex)
	}
	if m.context.Card.Front != "Q1" {
		t.Errorf("after h: Card.Front = %q, want Q1", m.context.Card.Front)
	}

	m, _ = sendKey(m, "h")
	if m.context.HistoryIndex != 0 {
		t.Errorf("after hh: HistoryIndex = %d, want 0", m.context.HistoryIndex)
	}

	m, _ = sendKey(m, "h")
	if m.context.HistoryIndex != 0 {
		t.Errorf("after hhh: HistoryIndex = %d, want 0 (no underflow)", m.context.HistoryIndex)
	}

	m, _ = sendKey(m, "l")
	if m.context.HistoryIndex != 1 {
		t.Errorf("after l: HistoryIndex = %d, want 1", m.context.HistoryIndex)
	}
}

func TestUpdate_KeyPress_Quit(t *testing.T) {
	m := newTestModel()

	m2, _ := sendKey(m, "q")
	if !m2.quitting {
		t.Error("q: quitting = false, want true")
	}

	m3, _ := sendKey(m, "ctrl+c")
	if !m3.quitting {
		t.Error("ctrl+c: quitting = false, want true")
	}

	m4 := newTestModel()
	m4.done = true
	m4, _ = sendKey(m4, "esc")
	if !m4.quitting {
		t.Error("esc: quitting = false, want true")
	}
}

// --- generateStage.Execute ---

func TestGenerateStageExecute_ResetsState(t *testing.T) {
	ctx := newTestContext()
	ctx.FailedAttempts = []string{"fail1", "fail2"}
	ctx.AgentTurn = 5
	ctx.SearchCount = 3

	err := generateStage{}.Execute(ctx)
	if err != nil {
		t.Fatalf("Execute() error = %v", err)
	}

	if ctx.FailedAttempts != nil {
		t.Errorf("FailedAttempts = %v, want nil", ctx.FailedAttempts)
	}
	if ctx.AgentTurn != 0 {
		t.Errorf("AgentTurn = %d, want 0", ctx.AgentTurn)
	}
	// SearchCount is NOT reset by Execute — "r" key handler resets it
	if ctx.SearchCount != 3 {
		t.Errorf("SearchCount = %d, want 3 (unchanged)", ctx.SearchCount)
	}
}
