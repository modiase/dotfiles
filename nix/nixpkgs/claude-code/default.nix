{ config, lib, ... }:
let
  settings = import ./settings.nix;
in
{
  config = lib.mkIf config.programs.claude-code.enable {
    programs.claude-code.settings = settings;
    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;
  };
}
