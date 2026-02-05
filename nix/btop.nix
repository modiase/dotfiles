{ config, pkgs, ... }:

{
  home.packages = with pkgs; [ btop ];

  xdg.configFile."btop/btop.conf".text = ''
    color_theme = "gruvbox_material_dark"
    theme_background = False
  '';
}
