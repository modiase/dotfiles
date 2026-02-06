{ pkgs, nvim-mcp }:
let
  nvim-mcp-bin = nvim-mcp.packages.${pkgs.system}.nvim-mcp;
in
pkgs.writeShellApplication {
  name = "nvim-mcp-connect";
  runtimeInputs = [
    nvim-mcp-bin
    pkgs.tmux
  ];
  text = builtins.readFile ./nvim-mcp-connect.sh;
}
