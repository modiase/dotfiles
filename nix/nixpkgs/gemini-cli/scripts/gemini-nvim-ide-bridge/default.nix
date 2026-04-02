{
  lib,
  buildGoModule,
  runCommand,
  tmuxNvimSelect,
  devlogsLibSrc,
}:

let
  combinedSrc = runCommand "gemini-nvim-ide-bridge-src" { } ''
    mkdir -p $out/gemini-nvim-ide-bridge $out/devlogs-lib
    cp -r ${./.}/* $out/gemini-nvim-ide-bridge/
    cp -r ${devlogsLibSrc}/* $out/devlogs-lib/
    sed -i 's|../../../devlogs-lib|../devlogs-lib|' $out/gemini-nvim-ide-bridge/go.mod
  '';
in
buildGoModule {
  pname = "gemini-nvim-ide-bridge";
  version = "0.2.0";

  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/gemini-nvim-ide-bridge";

  vendorHash = "sha256-dBZB9pRUL9YE8sQ9Gw6isdPEYD9XX0jlJbfLNyG6ybc=";

  ldflags = [
    "-X main.tmuxNvimSelectBin=${tmuxNvimSelect}/bin/tmux-nvim-select"
  ];

  meta = with lib; {
    description = "A bridge between Gemini CLI IDE protocol and Neovim RPC";
    license = licenses.mit;
    maintainers = [ ];
  };
}
