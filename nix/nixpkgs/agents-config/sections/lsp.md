## LSP Diagnostics (MANDATORY if nvim MCP available)

**If the nvim MCP server is available and operational**, you MUST check LSP diagnostics on changed files after each round of changes. This is not optional.

### Requirements

- **Errors (severity 1)**: MUST be fixed before considering work complete
- **Warnings/Hints (severity 2+)**: Ignore - often false positives or stylistic

### How to Check

1. Connect to nvim via `mcp__nvim__connect` with `target=auto` (the proxy discovers the socket automatically)
2. For each changed file, use `mcp__nvim__navigate` to open it in Neovim (this ensures LSP attaches)
3. Call `mcp__nvim__wait_for_lsp_ready` once — if it fails, proceed anyway
4. Use `mcp__nvim__buffer_diagnostics` on the opened buffer
5. **Prefer standalone LSP MCP servers** when available for the filetype (e.g., `mcp__lsp-lua__*`, `mcp__lsp-nix__*`) — they are more reliable than the nvim-based workflow above

### When to Skip

- If `mcp__nvim__get_targets` returns no targets and LSP MCP servers fail to start
- If the user explicitly instructs you to skip
- For file types without LSP support
