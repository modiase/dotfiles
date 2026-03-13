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
    export DEVLOGS_COMPONENT="tmux-nvim-select"
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    ${builtins.readFile ./tmux-nvim-select.sh}
  '';
}
