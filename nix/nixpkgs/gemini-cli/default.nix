{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.gemini-cli;

  ding = pkgs.callPackage ../ding { };
  secrets = pkgs.callPackage ../secrets { };
  ntfy-me = pkgs.callPackage ../ntfy-me { inherit secrets ding; };

  hookScript = pkgs.writeShellApplication {
    name = "gemini-hook";
    runtimeInputs = [
      ding
      ntfy-me
    ];
    text = builtins.readFile ./scripts/hook.sh;
  };

  hookBin = "${hookScript}/bin/gemini-hook";

  settings = import ./settings.nix { inherit hookBin; };
  settingsJson = pkgs.writeText "gemini-settings.json" (builtins.toJSON settings);

  policyRules = import ./policies.nix;
  tomlFormat = pkgs.formats.toml { };
  policyFile = tomlFormat.generate "managed.toml" { rule = policyRules; };

  agentsDir = "$HOME/.agents";
in
{
  options.dotfiles.gemini-cli = {
    enable = lib.mkEnableOption "Gemini CLI with extensions";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.gemini-cli;
      description = "Gemini CLI package. Set null to skip installation.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = lib.optional (cfg.package != null) cfg.package;

      file.".gemini/settings.json".source = settingsJson;
      file.".gemini/policies/managed.toml".source = policyFile;

      activation.gemini-agent-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD ln -sfn "${agentsDir}/AGENTS.md" "$HOME/.gemini/AGENTS.md"
        $DRY_RUN_CMD ln -sfn "${agentsDir}/skills" "$HOME/.gemini/skills"
      '';
    };
  };
}
