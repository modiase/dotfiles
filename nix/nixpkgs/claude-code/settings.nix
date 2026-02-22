{
  theme = "ANSI Dark";
  alwaysThinkingEnabled = true;
  enabledPlugins = {
    "gopls-lsp@claude-plugins-official" = true;
  };
  permissions = {
    deny = [
      "Bash(gcloud secrets versions access:*)"
      "Bash(secrets get:*)"
      "Bash(sed -i *)"
      "Bash(sed --in-place *)"
    ];
    allow = [
      # Nix
      "Bash(nix eval:*)"
      "Bash(nix build:*)"
      "Bash(nix flake show:*)"
      "Bash(nix flake metadata:*)"
      "Bash(nix flake check:*)"
      "Bash(nix-instantiate:*)"
      "Bash(nix-build:*)"
      "Bash(nixos-option:*)"

      # Git (read-only)
      "Bash(git status:*)"
      "Bash(git log:*)"
      "Bash(git diff:*)"
      "Bash(git show:*)"
      "Bash(git branch:*)"
      "Bash(git remote:*)"
      "Bash(git rev-parse:*)"
      "Bash(git ls-files:*)"
      "Bash(git ls-tree:*)"
      "Bash(git stash list:*)"
      "Bash(git tag:*)"
      "Bash(git describe:*)"
      "Bash(git shortlog:*)"
      "Bash(git config:*)"
      "Bash(git blame:*)"
      "Bash(git reflog:*)"
      "Bash(git worktree list:*)"
      "Bash(git -C :* status:*)"
      "Bash(git -C :* log:*)"
      "Bash(git -C :* diff:*)"
      "Bash(git -C :* show:*)"
      "Bash(git -C :* branch:*)"
      "Bash(git -C :* remote:*)"
      "Bash(git -C :* rev-parse:*)"
      "Bash(git -C :* ls-files:*)"
      "Bash(git -C :* ls-tree:*)"

      # Filesystem (read-only)
      "Bash(ls:*)"
      "Bash(cat:*)"
      "Bash(head:*)"
      "Bash(tail:*)"
      "Bash(wc:*)"
      "Bash(stat:*)"
      "Bash(realpath:*)"
      "Bash(dirname:*)"
      "Bash(basename:*)"
      "Bash(readlink:*)"
      "Bash(fd:*)"
      "Bash(rg:*)"
      "Bash(find:*)"
      "Bash(grep:*)"
      "Bash(tree:*)"
      "Bash(eza:*)"
      "Bash(od:*)"
      "Bash(sed:*)"
      "Bash(echo:*)"
      "Bash(printf:*)"

      # Build/lint (read-only)
      "Bash(go build:*)"
      "Bash(go vet:*)"
      "Bash(go test:*)"
      "Bash(go list:*)"
      "Bash(go mod tidy:*)"
      "Bash(make:*)"
      "Bash(pre-commit:*)"
      "Bash(jq:*)"
      "Bash(yq:*)"
      "Bash(curl:*)"
      "Bash(wget:*)"

      # GCloud logging (read-only)
      "Bash(gcloud logging read:*)"
      "Bash(gcloud logging logs list:*)"
      "Bash(gcloud logging buckets list:*)"
      "Bash(gcloud logging buckets describe:*)"
      "Bash(gcloud logging locations list:*)"
      "Bash(gcloud logging locations describe:*)"
      "Bash(gcloud logging metrics list:*)"
      "Bash(gcloud logging metrics describe:*)"
      "Bash(gcloud logging operations list:*)"
      "Bash(gcloud logging operations describe:*)"
      "Bash(gcloud logging resource-descriptors list:*)"
      "Bash(gcloud logging scopes list:*)"
      "Bash(gcloud logging scopes describe:*)"
      "Bash(gcloud logging settings describe:*)"
      "Bash(gcloud logging sinks list:*)"
      "Bash(gcloud logging sinks describe:*)"
      "Bash(gcloud logging views list:*)"
      "Bash(gcloud logging views describe:*)"
      "Bash(gcloud logging links list:*)"
      "Bash(gcloud logging links describe:*)"

      # GCloud other (read-only)
      "Bash(gcloud compute instances list:*)"
      "Bash(gcloud compute instances describe:*)"
      "Bash(gcloud projects describe:*)"
      "Bash(gcloud config list:*)"
      "Bash(gcloud storage ls:*)"

      # System inspection
      "Bash(systemctl status:*)"
      "Bash(systemctl show:*)"
      "Bash(systemctl list-units:*)"
      "Bash(systemctl list-unit-files:*)"
      "Bash(journalctl:*)"
      "Bash(which:*)"
      "Bash(type:*)"
      "Bash(file:*)"
      "Bash(uname:*)"
      "Bash(hostname:*)"
      "Bash(env:*)"
      "Bash(printenv:*)"
      "Bash(id:*)"
      "Bash(whoami:*)"
      "Bash(df:*)"
      "Bash(du:*)"
      "Bash(free:*)"
      "Bash(uptime:*)"
      "Bash(ps:*)"
      "Bash(pgrep:*)"
      "Bash(lsof:*)"

      # MCP tools (read-only)
      "mcp__exa__*"
      "mcp__nixos__*"

      # Documentation domains
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
    SessionStart = [
      {
        matcher = "compact";
        hooks = [
          {
            type = "command";
            command = "cat ~/.agents/AGENTS.md 2>/dev/null; cat CLAUDE.md 2>/dev/null; true";
          }
        ];
      }
    ];
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
