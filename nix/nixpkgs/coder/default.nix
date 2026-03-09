{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.opencode;

  opencodeConfig = pkgs.writeText "opencode.json" (builtins.readFile ./config/opencode.json);

  # SDK requires an API key even though herakles doesn't validate it
  authJson = pkgs.writeText "opencode-auth.json" (
    builtins.toJSON {
      herakles = {
        type = "api";
        key = "not-needed";
      };
    }
  );

  tuiConfig = pkgs.writeText "opencode-tui.json" (builtins.readFile ./config/tui.json);

  agentsDir = "$HOME/.agents";
in
{
  options.dotfiles.opencode = {
    enable = lib.mkEnableOption "opencode with extensions";
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ pkgs.opencode ];

      file.".config/opencode/opencode.json".source = opencodeConfig;
      file.".config/opencode/tui.json".source = tuiConfig;

      activation = {
        opencode-auth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p "$HOME/.local/share/opencode"
          $DRY_RUN_CMD cp -f "${authJson}" "$HOME/.local/share/opencode/auth.json"
          $DRY_RUN_CMD chmod u+w "$HOME/.local/share/opencode/auth.json"
        '';

        opencode-agent-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ln -sfn "${agentsDir}/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
          $DRY_RUN_CMD ln -sfn "${agentsDir}/skills" "$HOME/.config/opencode/skills"
        '';
      };
    };
  };
}
