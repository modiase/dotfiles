{ pkgs, lib, ... }:

let
  secretsmanager = pkgs.callPackage ../secretsmanager { };
in
pkgs.buildGoModule {
  pname = "ankigen";
  version = "2.0.0";

  src = ./.;

  vendorHash = "sha256-8D+zjbn8SuJTDJeqVCr56E9fcwIL3pv93wj4VJaEIcc=";

  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/ankigen \
      --prefix PATH : ${lib.makeBinPath [ secretsmanager ]}
  '';

  meta = with lib; {
    description = "Generate Anki flashcards using AI with web search";
    mainProgram = "ankigen";
  };
}
