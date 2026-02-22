{
  config,
  lib,
  ...
}:
let
  cfg = config.dotfiles.agents-config;
in
{
  options.dotfiles.agents-config = {
    enable = lib.mkEnableOption "Cross-agent configuration (AGENTS.md and skills)";
  };

  config = lib.mkIf cfg.enable {
    home.file.".agents/AGENTS.md".source = ./AGENTS.md;
    home.file.".agents/skills/cli-tools/SKILL.md".source = ./skills/cli-tools/SKILL.md;
  };
}
