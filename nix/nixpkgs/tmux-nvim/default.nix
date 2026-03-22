{ pkgs, ... }:
let
  devlogsLib = pkgs.callPackage ../devlogs-lib { };
in
pkgs.writeShellApplication {
  name = "tmux-nvim-select";
  runtimeInputs = with pkgs; [
    gum
    coreutils
    gnugrep
    tmux
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init tmux-nvim-select
    ${builtins.readFile ./tmux-nvim-select.sh}
  '';
}
