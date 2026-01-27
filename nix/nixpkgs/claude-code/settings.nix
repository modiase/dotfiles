{
  theme = "ANSI Dark";
  alwaysThinkingEnabled = true;
  enabledPlugins = {
    "gopls-lsp@claude-plugins-official" = true;
  };
  permissions = {
    allow = [
      "mcp__exa__web_search_exa"
      "mcp__exa__get_code_context_exa"
      "mcp__exa__company_research_exa"
      "WebFetch(domain:crates.io)"
      "WebFetch(domain:developer.mozilla.org)"
      "WebFetch(domain:docs.anthropic.com)"
      "WebFetch(domain:docs.docker.com)"
      "WebFetch(domain:docs.python.org)"
      "WebFetch(domain:docs.rs)"
      "WebFetch(domain:github.com)"
      "WebFetch(domain:home-assistant.io)"
      "WebFetch(domain:huggingface.co)"
      "WebFetch(domain:kubernetes.io)"
      "WebFetch(domain:learn.microsoft.com)"
      "WebFetch(domain:nixos.org)"
      "WebFetch(domain:nixos.wiki)"
      "WebFetch(domain:npmjs.com)"
      "WebFetch(domain:pkg.go.dev)"
      "WebFetch(domain:postgresql.org)"
      "WebFetch(domain:pypi.org)"
      "WebFetch(domain:pytorch.org)"
      "WebFetch(domain:raw.githubusercontent.com)"
      "WebFetch(domain:redis.io)"
      "WebFetch(domain:tensorflow.org)"
      "WebFetch(domain:wiki.nixos.org)"
    ];
  };
  hooks = {
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "command -v ding >/dev/null && ding --focus-pane -w 'Claude Code' -i '#{t_window_name}' -m 'Agent stopped' >/dev/null || true";
          }
        ];
      }
    ];
    PermissionRequest = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "command -v ding >/dev/null && ding --focus-pane -i 'Claude Code' -w '#{t_window_name}' -m 'Permission needed' -t request >/dev/null || true";
          }
        ];
      }
    ];
  };
}
