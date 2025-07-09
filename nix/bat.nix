{ config, pkgs, ... }:

{
  programs.bat = {
    enable = true;
    config = {
      theme = "Nord";
      style = "plain";
      pager = "less -RFXS";
    };
  };
}
