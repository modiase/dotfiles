{ config, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      sensible
      nord
      vim-tmux-navigator
      resurrect
      continuum
      sysstat
    ];
    extraConfig = ''
      # remap prefix from 'C-b' to 'C-a'
      unbind C-b
      set-option -g prefix C-a
      bind-key C-a send-prefix

      bind -n S-M-Up resize-pane -U 5
      bind -n S-M-Down resize-pane -D 5
      bind -n S-M-Left resize-pane -L 5
      bind -n S-M-Right resize-pane -R 5

      # split penes using | and -
      bind = split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # reload config file (change file location to your the tmux.conf you want to use)
      bind r source-file ~/.config/tmux/tmux.conf

      set -g mouse on

      # Clear terminal using <prefix> + C-l
      bind C-l send-keys 'C-l'

      set -g window-active-style 'fg=#ffffff'
      set -g window-style 'fg=#413c77'

      set -g default-terminal "alacritty"
      set -g terminal-overrides ',*alacritty*:Tc'
    '';
  };
}
