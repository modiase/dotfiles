package components

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
)

type SearchState struct {
	Active    bool
	Query     string
	LastQuery string
	Direction int   // 1 = forward (/), -1 = backward (?)
	Matches   []int // Line indices matching query
	Current   int   // Current match index (-1 if no matches)
}

func NewSearchState() SearchState {
	return SearchState{
		Direction: 1,
		Current:   -1,
	}
}

func (s *SearchState) NeedsUpdate() bool {
	return s.Active && s.Query != s.LastQuery
}

func (s *SearchState) FindMatches(lines []string) {
	s.LastQuery = s.Query
	s.Matches = nil
	s.Current = -1
	if s.Query == "" {
		return
	}
	query := strings.ToLower(s.Query)
	for i, line := range lines {
		if strings.Contains(strings.ToLower(line), query) {
			s.Matches = append(s.Matches, i)
		}
	}
	if len(s.Matches) > 0 {
		if s.Direction == 1 {
			s.Current = 0
		} else {
			s.Current = len(s.Matches) - 1
		}
	}
}

func (s *SearchState) NextMatch() int {
	if len(s.Matches) == 0 {
		return -1
	}
	s.Current = (s.Current + 1) % len(s.Matches)
	return s.Matches[s.Current]
}

func (s *SearchState) PrevMatch() int {
	if len(s.Matches) == 0 {
		return -1
	}
	s.Current--
	if s.Current < 0 {
		s.Current = len(s.Matches) - 1
	}
	return s.Matches[s.Current]
}

func (s *SearchState) CurrentLine() int {
	if s.Current < 0 || s.Current >= len(s.Matches) {
		return -1
	}
	return s.Matches[s.Current]
}

func (s *SearchState) MatchCount() int {
	return len(s.Matches)
}

func (s *SearchState) Reset() {
	s.Active = false
	s.Query = ""
	s.LastQuery = ""
	s.Matches = nil
	s.Current = -1
}

func (s *SearchState) IsMatchingLine(lineIndex int) bool {
	for _, m := range s.Matches {
		if m == lineIndex {
			return true
		}
	}
	return false
}

func (s *SearchState) HighlightContent(lines []string) string {
	if len(s.Matches) == 0 {
		return strings.Join(lines, "\n")
	}

	highlightStyle := lipgloss.NewStyle().Background(lipgloss.Color("62")).Foreground(lipgloss.Color("255"))
	var result []string
	for i, line := range lines {
		if s.IsMatchingLine(i) {
			result = append(result, highlightStyle.Render(line))
		} else {
			result = append(result, line)
		}
	}
	return strings.Join(result, "\n")
}

func (s *SearchState) RenderSearchBar(width int) string {
	if !s.Active {
		return ""
	}

	prompt := "/"
	if s.Direction == -1 {
		prompt = "?"
	}

	style := lipgloss.NewStyle().
		Foreground(lipgloss.Color("99")).
		Bold(true)

	matchInfo := ""
	if len(s.Matches) > 0 {
		matchInfo = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Render(" [%d/%d]")
		matchInfo = strings.Replace(matchInfo, "%d/%d", string(rune('0'+s.Current+1))+"/"+string(rune('0'+len(s.Matches))), 1)
	} else if s.Query != "" {
		matchInfo = lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Render(" [no matches]")
	}

	return style.Render(prompt+s.Query) + matchInfo
}

func (s *SearchState) RenderSearchBarFormatted(width int) string {
	if !s.Active {
		return ""
	}

	prompt := "/"
	if s.Direction == -1 {
		prompt = "?"
	}

	style := lipgloss.NewStyle().
		Foreground(lipgloss.Color("99")).
		Bold(true)

	var matchInfo string
	if len(s.Matches) > 0 {
		matchStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
		matchInfo = matchStyle.Render(" [" + itoa(s.Current+1) + "/" + itoa(len(s.Matches)) + "]")
	} else if s.Query != "" {
		matchInfo = lipgloss.NewStyle().
			Foreground(lipgloss.Color("9")).
			Render(" [no matches]")
	}

	return style.Render(prompt+s.Query) + matchInfo
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var result []byte
	for n > 0 {
		result = append([]byte{byte('0' + n%10)}, result...)
		n /= 10
	}
	return string(result)
}
