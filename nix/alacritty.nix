{ config, pkgs, ... }:

{
  programs.alacritty = {
    enable = true;
    settings = {
      general.live_config_reload = true;
      terminal.shell.program = "${pkgs.zsh}/bin/zsh";
      colors = {
        bright = {
          black = "#4c566a";
          blue = "#81a1c1";
          cyan = "#8fbcbb";
          green = "#a3be8c";
          magenta = "#b48ead";
          red = "#bf616a";
          white = "#eceff4";
          yellow = "#ebcb8b";
        };
        cursor = {
          cursor = "#d8dee9";
          text = "#2e3440";
        };
        dim = {
          black = "#373e4d";
          blue = "#68809a";
          cyan = "#6d96a5";
          green = "#809575";
          magenta = "#8c738c";
          red = "#94545d";
          white = "#aeb3bb";
          yellow = "#b29e75";
        };
        normal = {
          black = "#3b4252";
          blue = "#81a1c1";
          cyan = "#88c0d0";
          green = "#a3be8c";
          magenta = "#b48ead";
          red = "#bf616a";
          white = "#e5e9f0";
          yellow = "#ebcb8b";
        };
        primary = {
          background = "#1c1e26";
          dim_foreground = "#a5abb6";
          foreground = "#d8dee9";
        };
        search.matches = {
          background = "#88c0d0";
          foreground = "CellBackground";
        };
        selection = {
          background = "#4c566a";
          text = "CellForeground";
        };
        vi_mode_cursor = {
          cursor = "#d8dee9";
          text = "#2e3440";
        };
      };
      font = {
        size = 12.0;
        bold.family = "Iosevka Nerd Font";
        italic.family = "Iosevka Nerd Font";
        normal.family = "Iosevka Nerd Font";
      };
      keyboard.bindings = [
        { chars = "º"; key = "Key0"; mods = "Alt"; }
        { chars = "¡"; key = "Key1"; mods = "Alt"; }
        { chars = "€"; key = "Key2"; mods = "Alt"; }
        { chars = "#"; key = "Key3"; mods = "Alt"; }
        { chars = "¢"; key = "Key4"; mods = "Alt"; }
        { chars = "∞"; key = "Key5"; mods = "Alt"; }
        { chars = "§"; key = "Key6"; mods = "Alt"; }
        { chars = "¶"; key = "Key7"; mods = "Alt"; }
        { chars = "•"; key = "Key8"; mods = "Alt"; }
        { chars = "ª"; key = "Key9"; mods = "Alt"; }
      ];
      window = {
        decorations = "transparent";
        dynamic_padding = true;
        padding = {
          x = 0;
          y = 0;
        };
      };
    };
  };
}