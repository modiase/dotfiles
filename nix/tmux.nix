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

      set -g status-style "bg=#2a2a2a,fg=#e0e0e0"
      set -g status-left "#[bg=#3a3a3a,fg=#a8d8ea] #S #[bg=#2a2a2a] "
      set -g status-right "#[fg=#707070]%H:%M #[fg=#a8d8ea]#h "
      set -g window-status-current-style "bg=#3a3a3a,fg=#a8d8ea,bold"
      set -g window-status-style "bg=#2a2a2a,fg=#707070"
      set -g window-status-format " #{?window_bell_flag,#[fg=#f6e3a1],}#I:#W#F "
      set -g window-status-current-format " #I:#W#F "
      set -g pane-border-style "fg=#3a3a3a"
      set -g pane-active-border-style "fg=#a8d8ea"
      set -g message-style "bg=#3a3a3a,fg=#e0e0e0"
    '';
  };

  home.file.".config/tmux/tmux-vscode.conf".text = commonTmuxConfig + ''
    bind r source-file ~/.config/tmux/tmux-vscode.conf

    set -g default-terminal "xterm-256color"
    set -g terminal-overrides ',xterm-256color:Tc'
    set -ga terminal-overrides ',*:XT:Smulx@:Setulc@'
    set -ga terminal-overrides ',*:setrgbf@:setrgbb@:setrgbaf@:setrgbab@'
    set -as terminal-features ',xterm-256color:clipboard'

    set -g status-style "bg=#2a2a2a,fg=#e0e0e0"
    set -g status-left "#[bg=#3a3a3a,fg=#a8d8ea] #S #[bg=#2a2a2a] "
    set -g status-right "#[fg=#707070]%H:%M #[fg=#a8d8ea]#h "
    set -g window-status-current-style "bg=#3a3a3a,fg=#a8d8ea,bold"
    set -g window-status-style "bg=#2a2a2a,fg=#707070"
    set -g window-status-format " #{?window_bell_flag,#[fg=#f6e3a1],}#I:#W#F "
    set -g window-status-current-format " #I:#W#F "
    set -g pane-border-style "fg=#3a3a3a"
    set -g pane-active-border-style "fg=#a8d8ea"
    set -g message-style "bg=#3a3a3a,fg=#e0e0e0"

    run-shell '${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux'
    run-shell '${pkgs.tmuxPlugins.vim-tmux-navigator}/share/tmux-plugins/vim-tmux-navigator/vim-tmux-navigator.tmux'
    run-shell '${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux'
    run-shell '${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux'
    run-shell '${pkgs.tmuxPlugins.sysstat}/share/tmux-plugins/sysstat/sysstat.tmux'
  '';
}
