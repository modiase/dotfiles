{ pkgs, lib, ... }:

let
  secrets = pkgs.callPackage ../secrets { };

  # Create combined source with semsearch in the right relative location
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

  vendorHash = "sha256-QtQakVn6aNlHMr/Fu9biVdm4rsrU14ADySPEU3XOH68=";

  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/ankigen \
      --prefix PATH : ${lib.makeBinPath [ secrets ]}
  '';

  meta = with lib; {
    description = "Generate Anki flashcards using AI with web search";
    mainProgram = "ankigen";
  };
}
