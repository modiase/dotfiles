# ankigen

CLI tool for generating Anki flashcards using AI models.

## Usage

```bash
ankigen [provider] [options] "question"
```

## Providers

- `claude` - Anthropic Claude (opus-4-5 / haiku-4-5)
- `chatgpt` - OpenAI GPT (gpt-4.1 / o4-mini)
- `gemini` - Google Gemini (2.5-pro / 2.5-flash)

## Options

- `-f, --fast` - Use cheaper/faster model variant
- `-w, --web` - Enable web search tools (Claude/ChatGPT only)
- `-t, --token N` - Max tokens (default: 2000)
- `-b, --no-cache` - Bypass system prompt cache
- `-d, --debug` - Enable debug output

## Examples

```bash
ankigen "What is Docker?"
ankigen claude -f "Quick question"
ankigen chatgpt -w "Recent SpaceX launch"
```

## Configuration

Requires API keys via secretsmanager:
- `ANTHROPIC_API_KEY` (pass: anthropic-api-key)
- `OPENAI_API_KEY` (pass: openai-api-key)
- `GEMINI_API_KEY` (pass: gemini-api-key)

System prompt: https://gist.githubusercontent.com/modiase/88cbb2e7947a4ae970a91d9e335ab59c/raw/anki.txt
