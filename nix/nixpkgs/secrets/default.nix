{
  python313,
  google-cloud-sdk,
  lib,
  stdenv,
  pass,
}:

let
  python = python313.withPackages (ps: [
    ps.click
    ps.cryptography
    ps.google-cloud-secret-manager
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
in
stdenv.mkDerivation {
  pname = "secrets";
  version = "2.0.0";
  src = ./secrets;

  buildInputs = [ python ];
  propagatedBuildInputs = [ google-cloud-sdk ] ++ lib.optionals stdenv.isLinux [ pass ];

  installPhase = ''
    mkdir -p $out/lib/secrets $out/bin $out/share/secrets/schemas

    cp -r . $out/lib/secrets/
    cp ${schemas}/share/secrets/schemas/*.json $out/share/secrets/schemas/

    cat > $out/bin/secrets << EOF
    #!${python}/bin/python
    import sys
    sys.path.insert(0, "$out/lib")
    from secrets.cli import main
    main()
    EOF
    chmod +x $out/bin/secrets
  '';

  meta = {
    description = "Secrets management with multiple backends and encryption";
    mainProgram = "secrets";
  };
}
