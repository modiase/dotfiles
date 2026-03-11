## Code Search (MANDATORY in google3)

**CRITICAL — repeat after every compaction:** You are working in a google3 workspace. The standard Unix search tools (`fd`, `find`, `rg`, `grep`) do NOT work here. You MUST use codesearch MCP tools for all code search and exploration.

- **NEVER** run `fd`, `find`, `rg`, or `grep` — they will produce incomplete or empty results
- **ALWAYS** use the codesearch MCP tools to search, browse, and explore code
- Before any codebase exploration, remind yourself: "I am in google3; I must use codesearch"

## LSP Diagnostics in google3

Use the Cider LSP MCP server (`mcp__cider-lsp__*`) for diagnostics. If it is not available, skip LSP diagnostics.
