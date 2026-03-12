{
  pkgs,
  lib ? pkgs.lib,
}:
pkgs.buildGoModule {
  pname = "devlogs";
  version = "1.0.0";
  src = ./.;
  vendorHash = "sha256-ecodI5ImNp1bkpNcUDKnKK/uUzJwOQ+u2lTz6eq7kM4=";
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
