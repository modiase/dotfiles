{ hookBin, shellcommandHookBin }:
{
  theme = "ANSI Dark";
  alwaysThinkingEnabled = true;
  enabledPlugins = {
    "gopls-lsp@claude-plugins-official" = true;
  };
  permissions = {
    deny = [
      # Secret access
      "Bash(gcloud secrets:*)"
      "Bash(secrets get:*)"
      "Read(~/.ssh/*)"

      # Destructive file edits
      "Bash(sed -i:*)"
      "Bash(sed -i':*)"
      "Bash(sed --in-place:*)"

      # Destructive git
      "Bash(git push:*)"
      "Bash(git commit:*)"
      "Bash(git reset --hard:*)"
      "Bash(git clean:*)"
      "Bash(git rebase:*)"
      "Bash(git merge:*)"

      # Destructive nix
      "Bash(nix-collect-garbage:*)"
      "Bash(nix store delete:*)"
      "Bash(nix store gc:*)"

      # Destructive gcloud
      "Bash(gcloud iam:*)"
      "Bash(gcloud storage cp:*)"
      "Bash(gcloud storage mv:*)"
      "Bash(gcloud storage rm:*)"
      "Bash(gcloud compute instances delete:*)"
      "Bash(gcloud compute instances create:*)"
    ];
    allow = [
      # Broad tool groups (deny list gates destructive subcommands)
      "Bash(git:*)"
      "Bash(nix:*)"
      "Bash(nix-instantiate:*)"
      "Bash(nix-build:*)"
      "Bash(nix-store:*)"
      "Bash(nix-prefetch-url:*)"
      "Bash(nixos-option:*)"
      "Bash(gcloud:*)"
      "Bash(go:*)"
      "Bash(gh:*)"

      # Filesystem
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

      # Text processing / utilities
      "Bash(awk:*)"
      "Bash(sort:*)"
      "Bash(uniq:*)"
      "Bash(xargs:*)"
      "Bash(date:*)"
      "Bash(timeout:*)"
      "Bash(tmux:*)"

      # Build/lint
      "Bash(make:*)"
      "Bash(pre-commit:*)"
      "Bash(jq:*)"
      "Bash(yq:*)"
      "Bash(curl:*)"
      "Bash(wget:*)"

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
      "Bash(test:*)"
      "Bash([:*)"

      # macOS-specific
      "Bash(launchctl list:*)"
      "Bash(/usr/bin/log show:*)"
      "Bash(mdfind:*)"

      # MCP tools
      "mcp__exa__*"
      "mcp__lsp-lua__*"
      "mcp__lsp-nix__*"
      "mcp__lsp-typescript__*"
      "mcp__nixos__*"
      "mcp__nvim__*"

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
    PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${shellcommandHookBin} --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
    SessionStart = [
      {
        matcher = "*";
        hooks = [
          {
            type = "command";
            command = "${hookBin} init --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
    Stop = [
      {
        hooks = [
          {
            type = "command";
            command = "${hookBin} stop --wrapper-id $WRAPPER_ID";
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
            command = "${hookBin} permission --wrapper-id $WRAPPER_ID";
          }
        ];
      }
    ];
  };
}
