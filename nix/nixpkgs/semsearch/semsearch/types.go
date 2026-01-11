package semsearch

// Config for semantic search.
type Config struct {
	GoogleAPIKey string
	GoogleCX     string
	EmbedURL     string
	EmbedModel   string
	Threshold    float64
	NumResults   int
}

// DefaultConfig returns sensible defaults.
func DefaultConfig() Config {
	return Config{
		EmbedURL:   "http://herakles.home:4000/v1",
		EmbedModel: "qwen-embed",
		Threshold:  0.7,
		NumResults: 5,
	}
}

// Result is a search result.
type Result struct {
	Title string  `json:"title"`
	URL   string  `json:"url"`
	Text  string  `json:"text"`
	Score float64 `json:"score,omitempty"`
}

type embeddingResponse struct {
	Data []struct {
		Embedding []float64 `json:"embedding"`
		Index     int       `json:"index"`
	} `json:"data"`
}

type googleSearchResponse struct {
	Items []struct {
		Title   string `json:"title"`
		Link    string `json:"link"`
		Snippet string `json:"snippet"`
	} `json:"items"`
}

// Logger for progress output.
type Logger interface {
	Logf(format string, args ...any)
}

type noopLogger struct{}

func (noopLogger) Logf(string, ...any) {}

// NoopLogger returns a silent logger.
func NoopLogger() Logger {
	return noopLogger{}
}
