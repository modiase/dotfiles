## Code Search (MANDATORY in google3)

**CRITICAL — repeat after every compaction:** You are working in a google3 workspace. For codebase-wide search and exploration, you MUST use codesearch MCP tools — `fd`, `find`, `rg`, and `grep` cannot index google3 and will produce incomplete or empty results.

- **Codebase search/exploration** — ALWAYS use codesearch MCP tools
- **Specific file targets** — `rg`, `grep`, `cat`, etc. are fine when you already know the exact path
- Before any codebase exploration, remind yourself: "I am in google3; I must use codesearch"

## LSP Diagnostics in google3

Use the Cider LSP MCP server (`mcp__cider-lsp__*`) for diagnostics. If it is not available, skip LSP diagnostics.
