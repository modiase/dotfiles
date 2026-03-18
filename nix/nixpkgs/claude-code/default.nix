{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;

  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  ding = pkgs.callPackage ../ding { };
  nvr = pkgs.callPackage ../nvr { };

  agentsCfg = config.dotfiles.agents-config;
  sharedMcpJson = pkgs.writeText "shared-mcp-servers.json" (builtins.toJSON agentsCfg.mcpServers);

  hookScript = pkgs.writeShellApplication {
    name = "claude-hook";
    runtimeInputs = [ ding ];
    text = ''
      export DEVLOGS_COMPONENT="claude-hook"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/hook.sh}
    '';
  };

  allowShellcommand = pkgs.callPackage ../allow-shellcommand { };

  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  planScriptInputs =
    with pkgs;
    [
      # keep-sorted start
      tmux
      # keep-sorted end
    ]
    ++ [
      nvr
      tmuxNvimSelect
    ];

  openPlanScript = pkgs.writeShellApplication {
    name = "nvim-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      export DEVLOGS_COMPONENT="nvim-plan"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/nvim-plan.sh}
    '';
  };

  closePlanScript = pkgs.writeShellApplication {
    name = "close-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      export DEVLOGS_COMPONENT="close-plan"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/close-plan.sh}
    '';
  };

  hookBin = "${hookScript}/bin/claude-hook";
  shellcommandHookBin = "${allowShellcommand}/bin/allow-shellcommand";

  baseSettings = import ./settings.nix { inherit hookBin shellcommandHookBin; };

  settings = baseSettings // {
    hooks = baseSettings.hooks // {
      PreToolUse = baseSettings.hooks.PreToolUse ++ [
        {
          matcher = "ExitPlanMode";
          hooks = [
            {
              type = "command";
              command = "${openPlanScript}/bin/nvim-plan";
            }
          ];
        }
      ];
      PostToolUse = [
        {
          matcher = "ExitPlanMode";
          hooks = [
            {
              type = "command";
              command = "${closePlanScript}/bin/close-plan";
            }
          ];
        }
      ];
    };
  };

  settingsJson = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);

  wrappedClaude = import ./wrapper.nix {
    inherit pkgs;
    claudeCodePkg = pkgs.claude-code;
    generateAgentsMd = agentsCfg.generateAgentsMd;
    configDir = cfg.configDir;
  };

  agentsDir = "$HOME/.agents";

  symlinkScript = configDir: ''
    $DRY_RUN_CMD ln -sfn "${agentsDir}/skills" "${configDir}/skills"
  '';
in
{
  options.dotfiles.claude-code = {
    enable = lib.mkEnableOption "Claude Code with extensions";
    configDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override config directory (default: ~/.claude)";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [
        wrappedClaude
      ];

      file.".claude/settings.json" = lib.mkIf (cfg.configDir == null) {
        source = settingsJson;
      };

      activation = {
        claude-agent-links = lib.mkIf (cfg.configDir == null) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] (symlinkScript "$HOME/.claude")
        );

        claude-config = lib.mkIf (cfg.configDir != null) (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD mkdir -p "${cfg.configDir}"
            $DRY_RUN_CMD ln -sf "${settingsJson}" "${cfg.configDir}/settings.json"
            ${symlinkScript cfg.configDir}
          ''
        );

        claude-mcp-servers = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          CLAUDE_JSON="$HOME/.claude.json"
          if [ -f "$CLAUDE_JSON" ]; then
            $DRY_RUN_CMD ${pkgs.jq}/bin/jq --argjson servers "$(cat ${sharedMcpJson})" \
              '.mcpServers = (.mcpServers // {}) * $servers' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp"
            $DRY_RUN_CMD mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON"
          fi
        '';
      };
    };
  };
}
