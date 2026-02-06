{ config, pkgs, ... }:

{
  programs.neovim = {
    enable = true;
    extraPackages = [ pkgs.tree-sitter ];
  };
}
