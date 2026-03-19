{
  pkgs,
  ...
}:
let
  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
in
pkgs.writeShellApplication {
  name = "nvim-mcp";
  runtimeInputs = [
    pkgs.nvim-mcp
    tmuxNvimSelect
    pkgs.python313
  ];
  text = ''
    export PYTHONPATH="${devlogsLib.python}/lib:''${PYTHONPATH:-}"
    exec python3 ${./nvim-mcp-proxy.py} --wrapper-id "''${WRAPPER_ID:-unknown}" "$@"
  '';
}
