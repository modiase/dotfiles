# ankigen

CLI tool for generating Anki flashcards using AI models with optional web search.

## Usage

```bash
ankigen [provider] [options] "question"
```

## Providers

- `local` - Local LLM via Ollama (default)
- `claude` - Anthropic Claude (opus-4-5 / haiku-4-5)
- `chatgpt` - OpenAI GPT (gpt-4.1 / o4-mini)
- `gemini` - Google Gemini (2.5-pro / 2.5-flash)

## Options

- `-f, --fast` - Use cheaper/faster model variant
- `--no-web` - Disable web search pipeline (direct generation)
- `--exa` - Use Exa API for search (default: DuckDuckGo)
- `-t, --tokens N` - Max tokens (default: 2000)
- `-b, --no-cache` - Bypass system prompt cache
- `-r, --raw` - Output raw JSON response (no TUI)
- `-d, --debug` - Enable debug output

## Pipeline

By default, the tool runs a multi-stage pipeline:

1. **Search Terms**: LLM generates 1-5 search queries
2. **Web Search**: DuckDuckGo (default) or Exa API (`--exa`)
3. **Summarize**: LLM condenses search results
4. **Generate**: LLM creates the flashcard

## TUI Mode

When not using `-r`, the tool displays an interactive TUI with:
- Progress spinner during generation
- Card display with front/back sections
- Key bindings:
  - `r` - Regenerate card
  - `c` - Copy both (tab-separated)
  - `f` - Copy front only
  - `b` - Copy back only
  - `q` - Quit

## Examples

```bash
ankigen "What is Docker?"                   # With web search (default)
ankigen claude -f "Quick question"          # Fast model
ankigen --no-web "Simple definition"        # Skip web search
ankigen -r "What is a closure?"             # Raw JSON output
```

## Configuration

Requires API keys via secretsmanager:
- `ANTHROPIC_API_KEY` (pass: anthropic-api-key)
- `OPENAI_API_KEY` (pass: openai-api-key)
- `GEMINI_API_KEY` (pass: gemini-api-key)
- `EXA_API_KEY` (pass: exa-api-key) - for web search

System prompt: https://gist.githubusercontent.com/modiase/88cbb2e7947a4ae970a91d9e335ab59c/raw/anki.txt
