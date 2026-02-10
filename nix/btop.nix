{ config, pkgs, ... }:

{
  home.packages = with pkgs; [ btop ];

  xdg.configFile."btop/btop.conf".text = ''
    color_theme = "TTY"
    theme_background = False
  '';
}
