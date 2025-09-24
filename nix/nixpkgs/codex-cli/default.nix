{
  pkgs,
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
}:

let
  platformInfo = {
    "x86_64-linux" = {
      target = "x86_64-unknown-linux-gnu";
      sha256 = "sha256-uz7BQsbBO0r3GrJaLmiz1tCE5HRT55QYnBlvTcmrqss=";
    };
    "aarch64-linux" = {
      target = "aarch64-unknown-linux-gnu";
      sha256 = "sha256-YJqnjiZALQ7DiI7PgABO8qb61zQ2JLApmE4r07SVaZQ=";
    };
    "x86_64-darwin" = {
      target = "x86_64-apple-darwin";
      sha256 = "sha256-BKvqqqL5KRKQfQ5/Fh/neDv+8VvsxFgRRTVNyIOAft8=";
    };
    "aarch64-darwin" = {
      target = "aarch64-apple-darwin";
      sha256 = "sha256-yZitmJdMATf6CfCUI78/Uvn6X853MfSJVr0I3AENJVc=";
    };
  };

  currentPlatform =
    platformInfo.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");
in

stdenv.mkDerivation rec {
  pname = "codex-cli";
  version = "0.40.0";

  src = fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${currentPlatform.target}.tar.gz";
    sha256 = currentPlatform.sha256;
  };

  sourceRoot = ".";

  nativeBuildInputs = [
    pkgs.gnutar
  ]
  ++ lib.optionals stdenv.isLinux [
    autoPatchelfHook
  ];

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc.lib
    pkgs.openssl
    pkgs.zlib
  ];

  installPhase = ''
    mkdir -p $out/bin
    tar -xzf $src
    cp codex-${currentPlatform.target} $out/bin/codex
    chmod +x $out/bin/codex
  '';

  meta = with lib; {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "codex";
  };
}
