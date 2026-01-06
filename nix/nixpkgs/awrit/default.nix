{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  bun,
  cacert,
  jq,
  ...
}:

let
  version = "2.0.3";

  src = fetchFromGitHub {
    owner = "chase";
    repo = "awrit";
    rev = "electron";
    hash = "sha256-SUPzVwtMi+5Jq28KzqjXNWJCZkgk9nHelLvHBh42JVo=";
  };

  nativeFilename = "awrit-native-rs.darwin-arm64.node";
  nativeSrc = fetchurl {
    url = "https://github.com/chase/awrit/releases/download/awrit-native-rs-${version}/${nativeFilename}";
    hash = "sha256-vdm350YVjtg1HdYw1P8QcH7EHQtP3MFRGfcqdBV7Rig=";
  };

  nodeModules = stdenv.mkDerivation {
    pname = "awrit-node-modules";
    inherit version src;
    nativeBuildInputs = [
      bun
      cacert
    ];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-8G5BSODVjsmX90AoR/UaeJz6GMBNq5ZAE2Vd0ursxm0=";
    dontFixup = true;

    buildPhase = ''
      export HOME=$TMPDIR
      export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
      cp ${nativeSrc} awrit-native-rs/${nativeFilename}
      bun install
    '';

    installPhase = ''
      mkdir -p $out
      cp -r node_modules src $out/
    '';
  };

in
stdenv.mkDerivation {
  pname = "awrit";
  inherit version src;
  nativeBuildInputs = [ bun ];

  buildPhase = ''
    cp -r ${nodeModules}/node_modules .
    chmod -R +w node_modules
    cp ${nativeSrc} awrit-native-rs/${nativeFilename}

    ${lib.optionalString stdenv.isDarwin ''
      plist="node_modules/electron/dist/Electron.app/Contents/Info.plist"
      [[ -f "$plist" ]] && substituteInPlace "$plist" --replace-quiet '</dict>' '<key>LSUIElement</key><true/></dict>' || true
    ''}

    export HOME=$TMPDIR
    mkdir -p dist

    ${bun}/bin/bun build src/index.ts src/preload.js \
      --outdir dist --target node --format cjs --sourcemap=inline \
      --external electron --external '../config.js' --external '*.node' \
      --external awrit-native-rs --external electron-chrome-extensions \
      --external electron-chrome-web-store

    substituteInPlace dist/index.js \
      --replace-quiet 'var __dirname = "/nix/var/nix/builds/' 'var __dirname = require("path").dirname(__filename); var __ignored = "/nix/var/nix/builds/'

    touch dist/kitty.css
    ${bun}/bin/bun node_modules/vite/bin/vite.js build -c src/runner/vite.config.ts
    ${jq}/bin/jq -r '.version' package.json > dist/version
    cp ${nativeSrc} node_modules/awrit-native-rs/${nativeFilename}
  '';

  installPhase = ''
    mkdir -p $out/lib/awrit $out/bin
    cp -r . $out/lib/awrit/

    ELECTRON=$(find node_modules/electron/dist -name "Electron" -o -name "electron" | head -1)
    cat > $out/bin/awrit << WRAPPER
    #!/usr/bin/env bash
    exec "$out/lib/awrit/$ELECTRON" "$out/lib/awrit/dist/index.js" --high-dpi-support=1 "\$@"
    WRAPPER
    chmod +x $out/bin/awrit
  '';

  meta = with lib; {
    description = "A full graphical web browser for Kitty terminal";
    homepage = "https://github.com/chase/awrit";
    license = licenses.bsd3;
    platforms = [ "aarch64-darwin" ];
    mainProgram = "awrit";
  };
}
