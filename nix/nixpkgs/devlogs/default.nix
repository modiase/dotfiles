{
  pkgs,
  lib ? pkgs.lib,
}:
pkgs.buildGoModule {
  pname = "devlogs";
  version = "1.0.0";
  src = ./.;
  vendorHash = "sha256-MruOp4aEtERdQo/24I5iNY7T67EcrIuR7p/gFkJr0M8=";
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
