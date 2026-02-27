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

  hookScript = pkgs.writeShellApplication {
    name = "claude-hook";
    runtimeInputs = [
      ding
      ntfy-me
    ];
    text = builtins.readFile ./scripts/hook.sh;
  };

  openPlanScript = pkgs.writeShellApplication {
    name = "nvim-plan";
    runtimeInputs = with pkgs; [
      jq
      neovim-remote
    ];
    text = builtins.readFile ./scripts/nvim-plan.sh;
  };

  hookBin = "${hookScript}/bin/claude-hook";

  baseSettings = import ./settings.nix { inherit hookBin; };

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
