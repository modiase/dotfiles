{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;

  ding = pkgs.callPackage ../ding { };
  secrets = pkgs.callPackage ../secrets { };
  ntfy-me = pkgs.callPackage ../ntfy-me { inherit secrets ding; };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  hookScript = pkgs.writeShellApplication {
    name = "claude-hook";
    runtimeInputs = [
      ding
      ntfy-me
    ];
    text = builtins.readFile ./scripts/hook.sh;
  };

  devnullHookScript = pkgs.writeShellApplication {
    name = "allow-devnull";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./scripts/allow-devnull.sh;
  };

  openPlanScript = pkgs.writeShellApplication {
    name = "nvim-plan";
    runtimeInputs = with pkgs; [
      # keep-sorted start
      jq
      neovim-remote
      # keep-sorted end
    ];
    text = builtins.readFile ./scripts/nvim-plan.sh;
  };

  hookBin = "${hookScript}/bin/claude-hook";
  devnullHookBin = "${devnullHookScript}/bin/allow-devnull";

  baseSettings = import ./settings.nix { inherit hookBin devnullHookBin; };

  settings = lib.recursiveUpdate baseSettings {
    hooks.PostToolUse = [
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
    runtimeInputs = [ getClaudeIdeEnv ];
    text = ''
      ${lib.optionalString (cfg.configDir != null) ''export CLAUDE_CONFIG_DIR="${cfg.configDir}"''}
      ide_env=$(get-claude-ide-env 2>/dev/null) || true
      if [ -n "$ide_env" ]; then
          eval "$ide_env"
          export CLAUDE_CODE_SSE_PORT ENABLE_IDE_INTEGRATION
      fi
      exec ${pkgs.claude-code}/bin/claude "$@"
    '';
  };

  agentsDir = "$HOME/.agents";

  symlinkScript = configDir: ''
    $DRY_RUN_CMD ln -sfn "${agentsDir}/AGENTS.md" "${configDir}/CLAUDE.md"
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
      packages = [ wrappedClaude ];

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
