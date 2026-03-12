{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;
  generateAgentsMd = config.dotfiles.agents-config.generateAgentsMd;

  ding = pkgs.callPackage ../ding { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
  nvimMcpWrapper = pkgs.callPackage ../nvim-mcp-wrapper { };

  hookScript = pkgs.writeShellApplication {
    name = "claude-hook";
    runtimeInputs = [ ding ];
    text = builtins.readFile ./scripts/hook.sh;
  };

  devnullHookScript = pkgs.writeShellApplication {
    name = "allow-devnull";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/allow-devnull.sh;
  };

  planScriptInputs =
    with pkgs;
    [
      # keep-sorted start
      neovim-remote
      tmux
      # keep-sorted end
    ]
    ++ [ tmuxNvimSelect ];

  openPlanScript = pkgs.writeShellApplication {
    name = "nvim-plan";
    runtimeInputs = planScriptInputs;
    text = builtins.readFile ./scripts/nvim-plan.sh;
  };

  closePlanScript = pkgs.writeShellApplication {
    name = "close-plan";
    runtimeInputs = planScriptInputs;
    text = builtins.readFile ./scripts/close-plan.sh;
  };

  hookBin = "${hookScript}/bin/claude-hook";
  devnullHookBin = "${devnullHookScript}/bin/allow-devnull";

  baseSettings = import ./settings.nix { inherit hookBin devnullHookBin; };

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

  getClaudeIdeEnv = pkgs.writeShellApplication {
    name = "get-claude-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.jq
      pkgs.neovim-remote
    ];
    text = builtins.readFile ./scripts/get-claude-ide-env.sh;
  };

  wrappedClaude = pkgs.writeShellApplication {
    name = "claude";
    runtimeInputs = [
      getClaudeIdeEnv
      generateAgentsMd
    ];
    text = ''
      ${lib.optionalString (cfg.configDir != null) ''export CLAUDE_CONFIG_DIR="${cfg.configDir}"''}
      ide_env=$(get-claude-ide-env 2>/dev/null) || true
      if [ -n "$ide_env" ]; then
          eval "$ide_env"
          export CLAUDE_CODE_SSE_PORT ENABLE_IDE_INTEGRATION
      fi
      agents_md=$(generate-agents-md --agent claude)
      exec ${pkgs.claude-code}/bin/claude --append-system-prompt "$agents_md" "$@"
    '';
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
        nvimMcpWrapper
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
      };
    };
  };
}
