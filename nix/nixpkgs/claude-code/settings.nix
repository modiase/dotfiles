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
      {
        rule = "Bash(gcloud secrets:*)";
        reason = "Secret access denied for security.";
      }
      {
        rule = "Bash(secrets get:*)";
        reason = "Secret access denied for security.";
      }
      "Read(~/.ssh/*)"

      # Destructive file edits
      {
        rule = "Bash(sed -i:*)";
        reason = "In-place file editing denied. Use the Edit tool instead.";
      }
      {
        rule = "Bash(sed -i':*)";
        reason = "In-place file editing denied. Use the Edit tool instead.";
      }
      {
        rule = "Bash(sed --in-place:*)";
        reason = "In-place file editing denied. Use the Edit tool instead.";
      }

      # Destructive git
      {
        rule = "Bash(git push:*)";
        reason = "Destructive git operation. Ask the user to run this manually.";
      }
      {
        rule = "Bash(git commit:*)";
        reason = "Use the Skill tool with /commit instead, or ask the user.";
      }
      {
        rule = "Bash(git reset --hard:*)";
        reason = "Destructive git operation. Ask the user to run this manually.";
      }
      {
        rule = "Bash(git clean:*)";
        reason = "Destructive git operation. Ask the user to run this manually.";
      }
      {
        rule = "Bash(git rebase:*)";
        reason = "Destructive git operation. Ask the user to run this manually.";
      }
      {
        rule = "Bash(git merge:*)";
        reason = "Destructive git operation. Ask the user to run this manually.";
      }

      # Destructive nix
      {
        rule = "Bash(nix-collect-garbage:*)";
        reason = "Destructive nix operation denied.";
      }
      {
        rule = "Bash(nix store delete:*)";
        reason = "Destructive nix operation denied.";
      }
      {
        rule = "Bash(nix store gc:*)";
        reason = "Destructive nix operation denied.";
      }

      # Destructive gcloud
      {
        rule = "Bash(gcloud iam:*)";
        reason = "Destructive gcloud operation denied.";
      }
      {
        rule = "Bash(gcloud storage cp:*)";
        reason = "Destructive gcloud storage operation denied.";
      }
      {
        rule = "Bash(gcloud storage mv:*)";
        reason = "Destructive gcloud storage operation denied.";
      }
      {
        rule = "Bash(gcloud storage rm:*)";
        reason = "Destructive gcloud storage operation denied.";
      }
      {
        rule = "Bash(gcloud compute instances delete:*)";
        reason = "Destructive gcloud compute operation denied.";
      }
      {
        rule = "Bash(gcloud compute instances create:*)";
        reason = "Destructive gcloud compute operation denied.";
      }

      # macOS defaults
      {
        rule = "Bash(defaults write:*)";
        reason = "Writing macOS defaults is denied.";
      }
      {
        rule = "Bash(defaults delete:*)";
        reason = "Deleting macOS defaults is denied.";
      }

      # Turing-complete interpreters
      {
        rule = "Bash(python3:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(python:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(node:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(ruby:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(perl:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(lua:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
      {
        rule = "Bash(go run:*)";
        reason = "Turing-complete interpreter denied. Use dedicated tools or ask the user.";
      }
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

      # Filesystem (creation, low-risk)
      "Bash(mktemp:*)"
      "Bash(mkdir:*)"
      "Bash(touch:*)"
      "Bash(cp:*)"
      "Bash(mv:*)"
      "Bash(chmod:*)"

      # Text processing / utilities
      "Bash(awk:*)"
      "Bash(sort:*)"
      "Bash(uniq:*)"
      "Bash(xargs:*)"
      "Bash(date:*)"
      "Bash(timeout:*)"
      "Bash(tmux:*)"
      "Bash(diff:*)"
      "Bash(cut:*)"
      "Bash(tr:*)"
      "Bash(paste:*)"
      "Bash(comm:*)"
      "Bash(column:*)"
      "Bash(tac:*)"
      "Bash(nl:*)"
      "Bash(fmt:*)"
      "Bash(fold:*)"
      "Bash(rev:*)"
      "Bash(expand:*)"
      "Bash(unexpand:*)"

      # Crypto/encoding
      "Bash(shasum:*)"
      "Bash(md5:*)"
      "Bash(base64:*)"
      "Bash(xxd:*)"
      "Bash(strings:*)"

      # Shell utilities
      "Bash(pwd:*)"
      "Bash(true:*)"
      "Bash(false:*)"
      "Bash(seq:*)"
      "Bash(tput:*)"
      "Bash(command:*)"
      "Bash(hash:*)"

      # Build/lint/dev tools
      "Bash(make:*)"
      "Bash(pre-commit:*)"
      "Bash(jq:*)"
      "Bash(yq:*)"
      "Bash(curl:*)"
      "Bash(wget:*)"
      "Bash(bat:*)"
      "Bash(shellcheck:*)"
      "Bash(tldr:*)"
      "Bash(man:*)"

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

      # Nix ecosystem
      "Bash(nix-shell:*)"
      "Bash(nix-prefetch-git:*)"

      # Network diagnostics
      "Bash(dig:*)"
      "Bash(nslookup:*)"
      "Bash(host:*)"

      # Archive inspection
      "Bash(tar:*)"
      "Bash(unzip:*)"
      "Bash(zipinfo:*)"

      # macOS-specific
      "Bash(launchctl list:*)"
      "Bash(/usr/bin/log show:*)"
      "Bash(mdfind:*)"
      "Bash(sw_vers:*)"
      "Bash(defaults read:*)"
      "Bash(scutil:*)"

      # Terminal image viewer
      "Bash(chafa:*)"

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
