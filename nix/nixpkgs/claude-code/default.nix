{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;

  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  attn = pkgs.callPackage ../attn { };
  nvr = pkgs.callPackage ../nvr { };

  agentsCfg = config.dotfiles.agents-config;
  sharedMcpJson = pkgs.writeText "shared-mcp-servers.json" (builtins.toJSON agentsCfg.mcpServers);

  hookScript = pkgs.writeShellApplication {
    name = "claude-hook";
    runtimeInputs = [
      attn
      pkgs.jq
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init claude-hook
      ${builtins.readFile ./scripts/hook.sh}
    '';
  };

  denyRulesJson = pkgs.writeText "deny-rules.json" (builtins.toJSON (import ./deny-rules.nix));

  allowShellcommand = pkgs.callPackage ../allow-shellcommand { inherit denyRulesJson; };

  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  planResponder = pkgs.callPackage ../agents-plan-responder { };

  planScriptInputs =
    with pkgs;
    [
      # keep-sorted start
      tmux
      util-linux
      # keep-sorted end
    ]
    ++ [
      nvr
      planResponder
      tmuxNvimSelect
    ];

  openPlanScript = pkgs.writeShellApplication {
    name = "nvim-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init nvim-plan
      ${builtins.readFile ./scripts/nvim-plan.sh}
    '';
  };

  closePlanScript = pkgs.writeShellApplication {
    name = "close-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init close-plan
      ${builtins.readFile ./scripts/close-plan.sh}
    '';
  };

  formatHookScript = pkgs.callPackage ../format-hook { name = "claude-format-hook"; };

  hookBin = "${hookScript}/bin/claude-hook";
  shellcommandHookBin = "${allowShellcommand}/bin/allow-shellcommand";
  formatHookBin = "${formatHookScript}/bin/claude-format-hook";

  settingsModule = import ./settings.nix { inherit hookBin shellcommandHookBin formatHookBin; };
  baseSettings = settingsModule.settings;

  settings = baseSettings // {
    hooks = baseSettings.hooks // {
      PreToolUse = baseSettings.hooks.PreToolUse ++ [
        {
          matcher = "ExitPlanMode";
          hooks = [
            {
              type = "command";
              command = "${openPlanScript}/bin/nvim-plan --wrapper-id $WRAPPER_ID";
            }
          ];
        }
      ];
      PostToolUse = baseSettings.hooks.PostToolUse ++ [
        {
          matcher = "ExitPlanMode";
          hooks = [
            {
              type = "command";
              command = "${closePlanScript}/bin/close-plan --wrapper-id $WRAPPER_ID";
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
    inherit (agentsCfg) generateAgentsMd;
    inherit (cfg) configDir;
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
