package semsearch

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"
)

// Search performs a web search for a single query.
func Search(query string, cfg Config) ([]Result, error) {
	return SearchMultiple([]string{query}, cfg)
}

// SearchMultiple performs a web search for multiple queries.
func SearchMultiple(queries []string, cfg Config) ([]Result, error) {
	var results []Result
	for _, query := range queries {
		r, err := googleSearch(query, cfg)
		if err != nil {
			return nil, fmt.Errorf("query %q: %w", query, err)
		}
		results = append(results, r...)
	}
	return results, nil
}

// SearchRaw performs a web search returning markdown.
func SearchRaw(queries []string, cfg Config) (string, error) {
	results, err := SearchMultiple(queries, cfg)
	if err != nil {
		return "", err
	}
	return FormatResults(results), nil
}

func googleSearch(query string, cfg Config) ([]Result, error) {
	if cfg.GoogleAPIKey == "" || cfg.GoogleCX == "" {
		return nil, fmt.Errorf("google API key and CX required")
	}

	u := fmt.Sprintf("https://www.googleapis.com/customsearch/v1?key=%s&cx=%s&q=%s&num=%d",
		cfg.GoogleAPIKey, cfg.GoogleCX, url.QueryEscape(query), cfg.NumResults)

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Get(u)
	if err != nil {
		return nil, err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("google API error %d: %s", resp.StatusCode, string(body))
	}

	var result googleSearchResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return nil, err
	}

	var results []Result
	for _, item := range result.Items {
		results = append(results, Result{
			Title: item.Title,
			URL:   item.Link,
			Text:  item.Snippet,
		})
	}
	return results, nil
}
