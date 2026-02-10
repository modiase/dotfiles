{ config, pkgs, ... }:

let
  colors = import ./colors.nix;

  commonTmuxConfig = ''
    unbind C-b
    set-option -g prefix C-a
    bind-key C-a send-prefix

    bind -n S-M-Up resize-pane -U 5
    bind -n S-M-Down resize-pane -D 5
    bind -n S-M-Left resize-pane -L 5
    bind -n S-M-Right resize-pane -R 5

    bind = split-window -h -c "#{pane_current_path}"
    bind - split-window -v -c "#{pane_current_path}"
    unbind '"'
    unbind %

    set -g mouse on
    bind C-l send-keys 'C-l'

    set -g window-active-style 'fg=#${colors.foreground}'
    set -g window-style 'fg=#${colors.foregroundDim}'

    set -g default-command ${pkgs.fish}/bin/fish
    set -g allow-passthrough all
    set -s set-clipboard on

    set -g monitor-bell on
    set -g bell-action other
  '';
in
{
  programs.tmux = {
    enable = true;
    clock24 = true;
    keyMode = "vi";
    plugins = with pkgs.tmuxPlugins; [
      sensible
      vim-tmux-navigator
      resurrect
      continuum
      sysstat
    ];
    extraConfig = commonTmuxConfig + ''
      bind r source-file ~/.config/tmux/tmux.conf

      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",xterm-ghostty:Tc,xterm-256color:Tc,tmux-256color:Tc"
      set -as terminal-features ',xterm-256color:clipboard,xterm-ghostty:clipboard,tmux-256color:clipboard'

      set -g status-style "bg=#${colors.base16.base01},fg=#${colors.foreground}"
      set -g status-left "#[bg=#${colors.base16.base02},fg=#${colors.base16.base0C}] #S #[bg=#${colors.base16.base01}] "
      set -g status-right "#[fg=#${colors.foregroundDim}]%H:%M #[fg=#${colors.base16.base0C}]#h "
      set -g window-status-current-style "bg=#${colors.base16.base02},fg=#${colors.base16.base0C},bold"
      set -g window-status-style "bg=#${colors.base16.base01},fg=#${colors.foregroundDim}"
      set -g window-status-format " #{?window_bell_flag,#[fg=#${colors.base16.base0B}],}#I:#W#F "
      set -g window-status-current-format " #I:#W#F "
      set -g pane-border-style "fg=#${colors.base16.base02}"
      set -g pane-active-border-style "fg=#${colors.base16.base0B}"
      set -g message-style "bg=#${colors.base16.base02},fg=#${colors.foreground}"
    '';
  };

}
