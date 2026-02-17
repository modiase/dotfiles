{
  python313,
  google-cloud-sdk,
  gnupg,
  lib,
  stdenv,
  pass,
  makeBinaryWrapper,
}:

let
  pythonDeps = ps: [
    ps.click
    ps.cryptography
    ps.google-cloud-secret-manager
    ps.loguru
    ps.rich
  ];
  python = python313.withPackages pythonDeps;
  testPython = python313.withPackages (ps: pythonDeps ps ++ [ ps.pytest ]);
  runtimeDeps = [ google-cloud-sdk ] ++ lib.optionals stdenv.isLinux [ pass ];
in
stdenv.mkDerivation {
  pname = "secrets";
  version = "2.0.0";
  src = ./.;

  nativeBuildInputs = [ makeBinaryWrapper ];
  buildInputs = [ python ];
  nativeCheckInputs = [ testPython ];
  propagatedBuildInputs = [ google-cloud-sdk ] ++ lib.optionals stdenv.isLinux [ gnupg ];

  buildPhase = ''
    mkdir -p bin
    cat > bin/secrets << EOF
    #!${testPython}/bin/python
    import sys
    sys.path.insert(0, "$PWD")
    from secrets.cli import main
    main()
    EOF
    chmod +x bin/secrets
  '';

  doCheck = true;
  checkPhase = ''
    PATH="$PWD/bin:$PATH" ${testPython}/bin/pytest test_unit.py test_integration.py -v
  '';

  installPhase = ''
    mkdir -p $out/lib/secrets $out/bin $out/share/secrets/schemas

    cp -r secrets/* $out/lib/secrets/
    cp schemas/*.json $out/share/secrets/schemas/

    cat > $out/bin/.secrets-unwrapped << EOF
    #!${python}/bin/python
    import sys
    sys.path.insert(0, "$out/lib")
    from secrets.cli import main
    main()
    EOF
    chmod +x $out/bin/.secrets-unwrapped

    makeBinaryWrapper $out/bin/.secrets-unwrapped $out/bin/secrets \
      --prefix PATH : ${lib.makeBinPath runtimeDeps}
  '';

  meta = {
    description = "Secrets management with multiple backends and encryption";
    mainProgram = "secrets";
  };
}
