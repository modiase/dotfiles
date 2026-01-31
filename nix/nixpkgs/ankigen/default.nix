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

  vendorHash = "sha256-msaYLbOFOK3xGDWK0t2+HnwH+8XHOKS4RIbgtDYA2tE=";

  nativeBuildInputs = [ pkgs.makeBinaryWrapper ];

  postInstall = ''
    wrapProgram $out/bin/ankigen \
      --argv0 ankigen \
      --prefix PATH : ${lib.makeBinPath [ secrets ]}
  '';

  meta = with lib; {
    description = "Generate Anki flashcards using AI with web search";
    mainProgram = "ankigen";
  };
}
