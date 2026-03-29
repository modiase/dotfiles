{ pkgs, lib, ... }:

pkgs.buildGoModule {
  pname = "anki-api";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-WA7PLEaT7lpBkIQHXbRSrQO7mfip4mRS7xMck6lVAFs=";

  env.CGO_ENABLED = 1;
  buildInputs = [ pkgs.sqlite ];

  meta = with lib; {
    description = "REST API for Anki collection management";
    mainProgram = "anki-api";
  };
}
