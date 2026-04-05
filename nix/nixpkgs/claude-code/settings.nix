{
  hookBin,
  shellcommandHookBin,
  formatHookBin,
}:
let
  denyRules = import ./deny-rules.nix;
in
{
  inherit denyRules;

  settings = {
    theme = "ANSI Dark";
    alwaysThinkingEnabled = true;
    enabledPlugins = {
      "gopls-lsp@claude-plugins-official" = true;
    };
    permissions = {
      deny = map (r: r.rule) denyRules ++ [
        "Read(~/.ssh/*)"
      ];
      allow = [
        # Git (read-only subcommands only)
        "Bash(git status:*)"
        "Bash(git diff:*)"
        "Bash(git log:*)"
        "Bash(git show:*)"
        "Bash(git blame:*)"
        "Bash(git shortlog:*)"
        "Bash(git grep:*)"
        "Bash(git branch:*)"
        "Bash(git tag:*)"
        "Bash(git remote:*)"
        "Bash(git rev-parse:*)"
        "Bash(git rev-list:*)"
        "Bash(git describe:*)"
        "Bash(git ls-files:*)"
        "Bash(git ls-tree:*)"
        "Bash(git ls-remote:*)"
        "Bash(git cat-file:*)"
        "Bash(git name-rev:*)"
        "Bash(git reflog:*)"
        "Bash(git stash list:*)"
        "Bash(git worktree list:*)"
        "Bash(git config --get:*)"
        "Bash(git config --list:*)"
        "Bash(git config -l:*)"
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
        "Bash(devlogs:*)"
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
      PostToolUse = [
        {
          matcher = "Edit|Write";
          hooks = [
            {
              type = "command";
              command = formatHookBin;
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
  };
}
