{
  writeShellApplication,
  symlinkJoin,
  makeWrapper,
  coreutils,
  google-cloud-sdk,
  gum,
  jq,
  openssl,
  pass,
  sqlite,
  stdenv,
  lib,
}:

let
  secrets-unwrapped = writeShellApplication {
    name = "secrets";
    runtimeInputs = [
      coreutils
      google-cloud-sdk
      gum
      jq
      openssl
      sqlite
    ]
    ++ lib.optionals stdenv.isLinux [
      pass
    ];
    text = builtins.readFile ./secrets.sh;
  };

  schemas = stdenv.mkDerivation {
    name = "secrets-schemas";
    src = ./schemas;
    installPhase = ''
      mkdir -p $out/share/secrets/schemas
      cp *.json $out/share/secrets/schemas/
    '';
  };
in
symlinkJoin {
  name = "secrets";
  paths = [
    secrets-unwrapped
    schemas
  ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/secrets \
      --set SCHEMA_DIR "$out/share/secrets/schemas"
  '';
}
