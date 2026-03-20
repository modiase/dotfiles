{ pkgs, lib, ... }:

let
  nvimMcpUpstream = pkgs.callPackage ../nvim-mcp { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
  combinedSrc = pkgs.runCommand "nvim-mcp-src" { } ''
    mkdir -p $out/nvim-mcp $out/devlogs-lib
    cp -r ${./.}/* $out/nvim-mcp/
    cp -r ${../devlogs-lib}/* $out/devlogs-lib/
  '';
in
pkgs.buildGoModule {
  pname = "nvim-mcp";
  version = "1.0.0";

  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/nvim-mcp";

  vendorHash = null;

  ldflags = [
    "-X main.nvimMcpBin=${nvimMcpUpstream}/bin/nvim-mcp"
    "-X main.tmuxNvimSelectBin=${tmuxNvimSelect}/bin/tmux-nvim-select"
  ];

  meta = with lib; {
    description = "JSON-RPC proxy for nvim-mcp with automatic Neovim socket discovery";
    mainProgram = "nvim-mcp";
  };
}
