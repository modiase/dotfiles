{ config, pkgs, ... }:

let
  colors = import ./colors.nix;
in
{
  programs.neovim = {
    enable = true;
    extraPackages = [ pkgs.tree-sitter ];
  };

  xdg.configFile."nvim/lua/colors.lua".text = ''
    return {
      background = "#${colors.background}",
      foreground = "#${colors.foreground}",
      foregroundDim = "#${colors.foregroundDim}",
      cursor = "#${colors.cursor}",
      cursorText = "#${colors.cursorText}",
      selection = "#${colors.selection}",

      base00 = "#${colors.base16.base00}",
      base01 = "#${colors.base16.base01}",
      base02 = "#${colors.base16.base02}",
      base03 = "#${colors.base16.base03}",
      base04 = "#${colors.base16.base04}",
      base05 = "#${colors.base16.base05}",
      base06 = "#${colors.base16.base06}",
      base07 = "#${colors.base16.base07}",
      base08 = "#${colors.base16.base08}",
      base09 = "#${colors.base16.base09}",
      base0A = "#${colors.base16.base0A}",
      base0B = "#${colors.base16.base0B}",
      base0C = "#${colors.base16.base0C}",
      base0D = "#${colors.base16.base0D}",
      base0E = "#${colors.base16.base0E}",
      base0F = "#${colors.base16.base0F}",
    }
  '';
}
