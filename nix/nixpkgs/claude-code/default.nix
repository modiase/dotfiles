{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf config.programs.claude-code.enable {
    programs.claude-code.settings = import ./settings.nix;
    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
  };
}
