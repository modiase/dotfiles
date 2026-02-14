{ pkgs, lib, ... }:

let
  combinedSrc = pkgs.runCommand "ankigen-src" { } ''
    mkdir -p $out/ankigen $out/semsearch
    cp -r ${./.}/* $out/ankigen/
    cp -r ${../semsearch}/* $out/semsearch/
  '';
in
pkgs.buildGoModule {
  pname = "ankigen";
  version = "2.0.0";

  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/ankigen";

  vendorHash = "sha256-7E8Em9BiZIkyfpQMzcfAEtwztC/ShtSwejFRFVfleYc=";

  meta = with lib; {
    description = "Generate Anki flashcards using AI with web search";
    mainProgram = "ankigen";
  };
}
