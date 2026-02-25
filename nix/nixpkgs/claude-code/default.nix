{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.claude-code;

  openPlanScript = pkgs.writeShellApplication {
    name = "open-plan-in-nvim";
    runtimeInputs = with pkgs; [
      jq
      neovim-remote
    ];
    text = builtins.readFile ./open-plan-in-nvim.sh;
  };

  baseSettings = import ./settings.nix;

  settings = lib.recursiveUpdate baseSettings {
    hooks.PostToolUse = [
      {
        matcher = "ExitPlanMode";
        hooks = [
          {
            type = "command";
            command = "${openPlanScript}/bin/open-plan-in-nvim";
          }
        ];
      }
    ];
  };

  settingsJson = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);

  wrappedClaude = pkgs.symlinkJoin {
    name = "claude";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = lib.optionalString (cfg.configDir != null) ''
      rm $out/bin/claude
      makeBinaryWrapper ${pkgs.claude-code}/bin/claude $out/bin/claude \
        --set CLAUDE_CONFIG_DIR "${cfg.configDir}"
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
