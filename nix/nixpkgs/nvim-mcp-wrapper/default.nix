{
  pkgs,
  ...
}:
let
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
in
pkgs.writeShellApplication {
  name = "nvim-mcp";
  runtimeInputs = [
    pkgs.nvim-mcp
    pkgs.inetutils
    tmuxNvimSelect
    pkgs.python313
  ];
  text = ''exec python3 ${./nvim-mcp-proxy.py} "$@"'';
}
