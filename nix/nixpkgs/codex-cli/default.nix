{
  pkgs,
  lib,
  fetchurl,
  stdenv,
  autoPatchelfHook,
}:

let
  repo = "openai/codex";
  releasesBase = "https://github.com/${repo}/releases/download";

  platformInfo = {
    "x86_64-linux" = {
      target = "x86_64-unknown-linux-gnu";
      sha256 = "sha256-QkAjKdvc6wRDFqghcPaFMbr8/0Ps7D2IUEGLLKZpMoc=";
    };
    "aarch64-linux" = {
      target = "aarch64-unknown-linux-gnu";
      sha256 = "sha256-FEYZc6OYs2l9yzVo+FdE/lbeAUtAojo/B5Fs//YiQQY=";
    };
    "x86_64-darwin" = {
      target = "x86_64-apple-darwin";
      sha256 = "sha256-irPhihawfuMrlVVw5UbpkNd73783MqxT22putEfw/6c=";
    };
    "aarch64-darwin" = {
      target = "aarch64-apple-darwin";
      sha256 = "sha256-m4xyPkVkdrM5SvPfez3JgmvnavE3OZlY3Ghs1cm2j/4=";
    };
  };

  currentPlatform =
    platformInfo.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");
in

stdenv.mkDerivation rec {
  pname = "codex-cli";
  version = "0.50.0";

  src = fetchurl {
    url = "${releasesBase}/rust-v${version}/codex-${currentPlatform.target}.tar.gz";
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
    homepage = "https://github.com/${repo}";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "codex";
  };
}
