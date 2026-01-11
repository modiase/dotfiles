package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/mattn/go-isatty"
	"github.com/spf13/cobra"
	"semsearch/semsearch"
)

var (
	threshold  float64
	numResults int
	embedURL   string
	embedModel string
	skipEmbed  bool
	jsonOutput bool
	quiet      bool
	noPager    bool
	readable   bool
)

type cliLogger struct{}

func (cliLogger) Logf(format string, args ...any) {
	if !quiet {
		fmt.Fprintf(os.Stderr, format+"\n", args...)
	}
}

func main() {
	rootCmd := &cobra.Command{
		Use:   "semsearch [flags] <query>",
		Short: "Semantic search using Google with embedding-based filtering",
		Long: `semsearch performs web searches using Google Custom Search and optionally
filters results using semantic embeddings to find the most relevant content.

Credentials are fetched via 'secrets get custom-search-api-key' and
'secrets get custom-search-api-id' by default. Override with env vars
SEMSEARCH_GOOGLE_API_KEY/SEMSEARCH_GOOGLE_CX or *_SECRET_NAME variants.
Results are formatted as markdown and piped to $PAGER when output is a terminal.`,
		Args: cobra.MinimumNArgs(0),
		RunE: runSearch,
	}

	rootCmd.Flags().Float64VarP(&threshold, "threshold", "t", 0.7, "Similarity threshold for filtering (0-1)")
	rootCmd.Flags().IntVarP(&numResults, "num-results", "n", 5, "Max results per search term")
	rootCmd.Flags().StringVarP(&embedURL, "embed-url", "e", "http://herakles.home:4000/v1", "Embedding API URL")
	rootCmd.Flags().StringVarP(&embedModel, "model", "m", "qwen-embed", "Embedding model name")
	rootCmd.Flags().BoolVar(&skipEmbed, "skip-embed", false, "Skip semantic filtering")
	rootCmd.Flags().BoolVarP(&jsonOutput, "json", "j", false, "Output as JSON")
	rootCmd.Flags().BoolVarP(&quiet, "quiet", "q", false, "Suppress progress output")
	rootCmd.Flags().BoolVar(&noPager, "no-pager", false, "Disable pager output")
	rootCmd.Flags().BoolVar(&readable, "readable", false, "Wrap text at 80 chars (default when using pager)")

	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func runSearch(cmd *cobra.Command, args []string) error {
	var queries []string

	if len(args) > 0 {
		queries = args
	} else if !isatty.IsTerminal(os.Stdin.Fd()) {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			if q := strings.TrimSpace(scanner.Text()); q != "" {
				queries = append(queries, q)
			}
		}
		if err := scanner.Err(); err != nil {
			return fmt.Errorf("reading stdin: %w", err)
		}
	}

	if len(queries) == 0 {
		return fmt.Errorf("no query provided")
	}

	cfg := semsearch.Config{
		GoogleAPIKey: getEnvOrSecret("SEMSEARCH_GOOGLE_API_KEY", "custom-search-api-key"),
		GoogleCX:     getEnvOrSecret("SEMSEARCH_GOOGLE_CX", "custom-search-api-id"),
		EmbedURL:     embedURL,
		EmbedModel:   embedModel,
		Threshold:    threshold,
		NumResults:   numResults,
	}

	log := cliLogger{}
	log.Logf("Searching for: %s", strings.Join(queries, ", "))

	results, err := semsearch.SearchMultiple(queries, cfg)
	if err != nil {
		return err
	}
	log.Logf("Found %d results", len(results))

	if !skipEmbed && semsearch.IsEmbedServerAvailable(cfg) {
		log.Logf("Filtering with threshold %.2f", threshold)
		filtered, err := semsearch.Filter(strings.Join(queries, " "), results, cfg, log)
		if err != nil {
			log.Logf("Filtering failed: %v, skipping", err)
		} else {
			results = filtered
		}
	} else if !skipEmbed {
		log.Logf("Embedding server unavailable, skipping filter")
	}

	var output string
	if jsonOutput {
		data, err := json.MarshalIndent(results, "", "  ")
		if err != nil {
			return err
		}
		output = string(data)
	} else {
		useReadable := readable || (!noPager && isatty.IsTerminal(os.Stdout.Fd()))
		if useReadable {
			output = formatReadable(results)
		} else {
			output = semsearch.FormatResults(results)
		}
	}

	return outputWithPager(output)
}

func outputWithPager(content string) error {
	if noPager || !isatty.IsTerminal(os.Stdout.Fd()) {
		fmt.Print(content)
		return nil
	}

	pager := os.Getenv("PAGER")
	if pager == "" {
		pager = "less"
	}

	cmd := exec.Command(pager)
	cmd.Stdin = strings.NewReader(content)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func formatReadable(results []semsearch.Result) string {
	var b strings.Builder
	for i, r := range results {
		if i > 0 {
			b.WriteString("\n---\n\n")
		}
		if r.Title != "" {
			b.WriteString("## " + r.Title + "\n")
		}
		if r.URL != "" {
			b.WriteString(r.URL + "\n")
		}
		if r.Text != "" {
			b.WriteString("\n" + wrapText(r.Text, 80) + "\n")
		}
	}
	return b.String()
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

func wrapText(text string, width int) string {
	var result strings.Builder
	for _, line := range strings.Split(text, "\n") {
		if len(line) <= width {
			result.WriteString(line + "\n")
			continue
		}
		words := strings.Fields(line)
		var current strings.Builder
		for _, word := range words {
			if current.Len() == 0 {
				current.WriteString(word)
			} else if current.Len()+1+len(word) <= width {
				current.WriteString(" " + word)
			} else {
				result.WriteString(current.String() + "\n")
				current.Reset()
				current.WriteString(word)
			}
		}
		if current.Len() > 0 {
			result.WriteString(current.String() + "\n")
		}
	}
	return strings.TrimRight(result.String(), "\n")
}
