## LSP Diagnostics (MANDATORY if nvim MCP available)

**If the nvim MCP server is available and operational**, you MUST check LSP diagnostics on changed files after each round of changes. This is not optional.

### Requirements

- **Errors (severity 1)**: MUST be fixed before considering work complete
- **Warnings/Hints (severity 2+)**: Ignore - often false positives or stylistic

### How to Check

1. For each changed file, use `mcp__nvim__navigate` to open it in Neovim (this ensures LSP attaches)
2. Call `mcp__nvim__wait_for_lsp_ready` once — if it fails, proceed anyway
3. Use `mcp__nvim__buffer_diagnostics` on the opened buffer
4. **Prefer standalone LSP MCP servers** when available for the filetype (e.g., `mcp__lsp-lua__*`, `mcp__lsp-nix__*`) — they are more reliable than the nvim-based workflow above

### When to Skip

- If nvim MCP tools return errors (the proxy handles connection transparently — errors indicate nvim is genuinely unavailable)
- If the user explicitly instructs you to skip
- For file types without LSP support
