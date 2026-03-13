{
  pkgs,
  lib ? pkgs.lib,
}:
pkgs.buildGoModule {
  pname = "devlogs";
  version = "1.0.0";
  src = ./.;
  vendorHash = "sha256-Q2+XCqLYd6ZVvgJJ7mxdofkEG6WyTZUz+2XEXxgrn4w=";
  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Live structured log viewer for devlogs";
    license = lib.licenses.mit;
    mainProgram = "devlogs";
  };
}
