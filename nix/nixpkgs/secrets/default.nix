{
  python313,
  google-cloud-sdk,
  gnupg,
  lib,
  stdenv,
  pass,
  makeWrapper,
}:

let
  python = python313.withPackages (ps: [
    ps.click
    ps.cryptography
    ps.google-cloud-secret-manager
    ps.loguru
    ps.rich
  ]);

  schemas = stdenv.mkDerivation {
    name = "secrets-schemas";
    src = ./schemas;
    installPhase = ''
      mkdir -p $out/share/secrets/schemas
      cp *.json $out/share/secrets/schemas/
    '';
  };

  runtimeDeps = [ google-cloud-sdk ] ++ lib.optionals stdenv.isLinux [ pass ];
in
stdenv.mkDerivation {
  pname = "secrets";
  version = "2.0.0";
  src = ./secrets;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ python ];
  propagatedBuildInputs = [
    google-cloud-sdk
  ]
  ++ lib.optionals stdenv.isLinux [ gnupg ];

  installPhase = ''
    mkdir -p $out/lib/secrets $out/bin $out/share/secrets/schemas

    cp -r . $out/lib/secrets/
    cp ${schemas}/share/secrets/schemas/*.json $out/share/secrets/schemas/

    cat > $out/bin/.secrets-unwrapped << EOF
    #!${python}/bin/python
    import sys
    sys.path.insert(0, "$out/lib")
    from secrets.cli import main
    main()
    EOF
    chmod +x $out/bin/.secrets-unwrapped

    makeWrapper $out/bin/.secrets-unwrapped $out/bin/secrets \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  meta = {
    description = "Secrets management with multiple backends and encryption";
    mainProgram = "secrets";
  };
}
