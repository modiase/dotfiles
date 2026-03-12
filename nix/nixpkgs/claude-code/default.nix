{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;

  ding = pkgs.callPackage ../ding { };
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

  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

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

  wrappedClaude = import ./wrapper.nix {
    inherit pkgs;
    claudeCodePkg = pkgs.claude-code;
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
