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

    bind -T copy-mode-vi Enter send -X copy-pipe-and-cancel 'yank > #{pane_tty}'
    bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-and-cancel 'yank > #{pane_tty}'
    bind -T copy-mode-vi y send -X copy-pipe-and-cancel 'yank > #{pane_tty}'
    bind -n DoubleClick1Pane { select-pane -t=; copy-mode -H; send -X select-word; run -d0.3; send -X copy-pipe-and-cancel 'yank > #{pane_tty}' }
  '';
in
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
    extraConfig = commonTmuxConfig + ''
      bind r source-file ~/.config/tmux/tmux.conf

      set -g default-terminal "tmux-256color"
      set -ga terminal-overrides ",xterm-ghostty:Tc,xterm-256color:Tc,tmux-256color:Tc"
      set -as terminal-features ',xterm-256color:clipboard,xterm-ghostty:clipboard,tmux-256color:clipboard'
    '';
  };

  home.file.".config/tmux/tmux-vscode.conf".text = commonTmuxConfig + ''
    bind r source-file ~/.config/tmux/tmux-vscode.conf

    set -g default-terminal "xterm-256color"
    set -g terminal-overrides ',xterm-256color:Tc'
    set -ga terminal-overrides ',*:XT:Smulx@:Setulc@'
    set -ga terminal-overrides ',*:setrgbf@:setrgbb@:setrgbaf@:setrgbab@'
    set -as terminal-features ',xterm-256color:clipboard'

    run-shell '${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux'
    run-shell '${pkgs.tmuxPlugins.nord}/share/tmux-plugins/nord/nord.tmux'
    run-shell '${pkgs.tmuxPlugins.vim-tmux-navigator}/share/tmux-plugins/vim-tmux-navigator/vim-tmux-navigator.tmux'
    run-shell '${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux'
    run-shell '${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux'
    run-shell '${pkgs.tmuxPlugins.sysstat}/share/tmux-plugins/sysstat/sysstat.tmux'
  '';
}
