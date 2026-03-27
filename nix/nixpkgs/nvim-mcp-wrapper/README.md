# nvim-mcp-wrapper

Go JSON-RPC proxy wrapping the upstream Rust `nvim-mcp` binary. Adds automatic
Neovim socket discovery, transparent auto-connection, and health polling.

## Auto socket discovery

On startup and during reconnection, the proxy calls `tmux-nvim-select -q`
(with a 5-second timeout) to resolve the Neovim socket path from the current
tmux window.

## `connect(target="auto")` interception

When a client sends a `tools/call` request for `connect` or `connect_tcp` with
`target` set to `""` or `"auto"`:

1. If already connected and the socket still exists, returns the cached
   connection ID
2. Otherwise, discovers the socket via `tmux-nvim-select`
3. Rewrites `params.arguments.target` to the resolved path
4. Forwards the modified request to the Rust binary

The proxy also auto-injects `connection_id` into subsequent tool calls so
clients don't need to track it.

## Health polling and reconnection

A background goroutine polls every 3 seconds:

- If the socket file disappears, clears connection state
- If a new socket is discovered, sends a `connect` request to the Rust binary

Internal auto-connect requests use `_auto_N` IDs and are filtered from client
responses.

## `--wrapper-id` stripping

The proxy accepts `--wrapper-id` via Go's `flag` package (so it doesn't error)
but strips it from the arguments passed through to the Rust binary. This keeps
the wrapper ID available in `pgrep` output without confusing the downstream
process.
