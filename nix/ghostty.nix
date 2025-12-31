{
  config,
  pkgs,
  lib,
  ...
}:

let
  colors = import ./colors.nix;

  sharedSettings = {
    font-family = "Iosevka Nerd Font";
    font-size = 12;
    window-decoration = "auto";
    macos-titlebar-style = "transparent";
    window-padding-x = 0;
    window-padding-y = 0;
    background = colors.background;
    foreground = colors.foreground;
    cursor-color = colors.cursor;
    cursor-text = colors.cursorText;
    selection-background = colors.selection;
    macos-option-as-alt = false;
    keybind = "cmd+shift+r=prompt_surface_title";
  };

  formatValue =
    v:
    if builtins.isBool v then
      (if v then "true" else "false")
    else if builtins.isInt v || builtins.isFloat v then
      toString v
    else
      v;

  toGhosttyConfig =
    settings:
    let
      settingLines = lib.mapAttrsToList (k: v: "${k} = ${formatValue v}") settings;
      paletteLines = map (p: "palette = ${p}") colors.palette;
    in
    lib.concatStringsSep "\n" (settingLines ++ paletteLines);
in
{
  programs.ghostty = lib.mkIf (!pkgs.stdenv.isDarwin) {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
    settings = sharedSettings // {
      palette = colors.palette;
    };
  };

  xdg.configFile."ghostty/config" = lib.mkIf pkgs.stdenv.isDarwin {
    text = toGhosttyConfig sharedSettings;
  };
}
