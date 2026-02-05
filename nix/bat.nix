{ config, pkgs, ... }:

{
  programs.bat = {
    enable = true;
    config = {
      theme = "gruvbox-dark";
      style = "plain";
      pager = "less -RFXS";
    };
  };
}
