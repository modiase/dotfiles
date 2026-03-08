{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "tmux-nvim-select";
  runtimeInputs = with pkgs; [
    gum
    coreutils
    gnugrep
    tmux
  ];
  text = builtins.readFile ./tmux-nvim-select.sh;
}
