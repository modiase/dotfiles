{
  lib,
  stdenv,
  python3,
  makeWrapper,
  google-cloud-sdk,
  jq,
}:

let
  pythonEnv = python3.withPackages (ps: [
    ps.aiohttp
    ps.click
    ps.google-cloud-pubsub
    ps.loguru
  ]);
in
stdenv.mkDerivation {
  pname = "security-scan";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/lib/security_scan $out/bin

    cp utils.py scanner.py notifiers.py main.py $out/lib/security_scan/
    echo "" > $out/lib/security_scan/__init__.py

    cat > $out/bin/.security-scan-unwrapped << 'WRAPPER'
    #!${pythonEnv}/bin/python3
    import sys
    sys.path.insert(0, "@out@/lib")
    from security_scan.main import main
    main()
    WRAPPER

    substituteInPlace $out/bin/.security-scan-unwrapped --replace-fail "@out@" "$out"
    chmod +x $out/bin/.security-scan-unwrapped

    makeWrapper $out/bin/.security-scan-unwrapped $out/bin/security-scan \
      --prefix PATH : ${
        lib.makeBinPath [
          google-cloud-sdk
          jq
        ]
      }
  '';

  meta = {
    description = "Security vulnerability scanner with NVD API integration";
    mainProgram = "security-scan";
  };
}
