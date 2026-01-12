package semsearch

import "strings"

// Filter removes results below the similarity threshold.
func Filter(question string, results []Result, cfg Config, log Logger) ([]Result, error) {
	if log == nil {
		log = NoopLogger()
	}

	if len(results) == 0 {
		log.Logf("No results to filter")
		return results, nil
	}
	log.Logf("Filtering %d results by semantic relevance", len(results))

	type paragraphInfo struct {
		resultIdx int
		paraIdx   int
		text      string
	}
	var allParagraphs []paragraphInfo
	resultParagraphs := make([][]string, len(results))

	for i, r := range results {
		paras := splitIntoParagraphs(r.Text)
		resultParagraphs[i] = paras
		for j, p := range paras {
			allParagraphs = append(allParagraphs, paragraphInfo{i, j, p})
		}
	}

	if len(allParagraphs) == 0 {
		log.Logf("No paragraphs found")
		return results, nil
	}

	texts := make([]string, len(allParagraphs)+1)
	texts[0] = question
	for i, p := range allParagraphs {
		texts[i+1] = p.text
	}

	embeddings, err := GetEmbeddings(texts, cfg)
	if err != nil {
		return nil, err
	}

	questionEmb := embeddings[0]

	keptParagraphs := make([][]string, len(results))
	for i := range keptParagraphs {
		keptParagraphs[i] = []string{}
	}

	for i, p := range allParagraphs {
		similarity := CosineSimilarity(questionEmb, embeddings[i+1])
		if similarity >= cfg.Threshold {
			keptParagraphs[p.resultIdx] = append(keptParagraphs[p.resultIdx], p.text)
		}
	}

	var focused []Result
	for i, r := range results {
		kept := keptParagraphs[i]
		total := len(resultParagraphs[i])
		if len(kept) > 0 {
			log.Logf("  [%d/%d paras] %s", len(kept), total, r.Title)
			r.Text = strings.Join(kept, "\n\n")
			focused = append(focused, r)
		} else {
			log.Logf("  [0/%d paras] %s (dropped)", total, r.Title)
		}
	}

	log.Logf("Kept %d/%d results with relevant paragraphs", len(focused), len(results))
	if len(focused) == 0 {
		log.Logf("No results above threshold, keeping all")
		return results, nil
	}
	return focused, nil
}

// FilterRaw filters markdown results.
func FilterRaw(question, rawResults string, cfg Config, log Logger) (string, error) {
	results := ParseResults(rawResults)
	filtered, err := Filter(question, results, cfg, log)
	if err != nil {
		return "", err
	}
	return FormatResults(filtered), nil
}

// ParseResults parses labelled search results.
func ParseResults(raw string) []Result {
	var results []Result
	var r Result
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		switch {
		case line == "":
			if r.Title != "" || r.URL != "" || r.Text != "" {
				results = append(results, r)
				r = Result{}
			}
		case strings.HasPrefix(line, "Title: "):
			r.Title = strings.TrimPrefix(line, "Title: ")
		case strings.HasPrefix(line, "URL: "):
			r.URL = strings.TrimPrefix(line, "URL: ")
		case strings.HasPrefix(line, "Text: "):
			r.Text = strings.TrimPrefix(line, "Text: ")
		}
	}
	if r.Title != "" || r.URL != "" || r.Text != "" {
		results = append(results, r)
	}
	return results
}

// FormatResults formats results as labelled text.
func FormatResults(results []Result) string {
	var b strings.Builder
	for i, r := range results {
		if i > 0 {
			b.WriteString("\n")
		}
		if r.Title != "" {
			b.WriteString("Title: " + r.Title + "\n")
		}
		if r.URL != "" {
			b.WriteString("URL: " + r.URL + "\n")
		}
		if r.Text != "" {
			b.WriteString("Text: " + r.Text + "\n")
		}
	}
	return b.String()
}

func splitIntoParagraphs(text string) []string {
	raw := strings.Split(text, "\n\n")
	var paragraphs []string
	for _, p := range raw {
		p = strings.TrimSpace(p)
		if len(p) > 50 {
			paragraphs = append(paragraphs, p)
		}
	}
	if len(paragraphs) == 0 && len(strings.TrimSpace(text)) > 0 {
		paragraphs = []string{strings.TrimSpace(text)}
	}
	return paragraphs
}
