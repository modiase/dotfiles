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
      sha256 = "sha256-N7qOby5yq9VZzOs0DWMZbWKLU7s2P2vs3uLwDhIeFRw=";
    };
    "aarch64-linux" = {
      target = "aarch64-unknown-linux-gnu";
      sha256 = "sha256-PLACEHOLDER-FOR-AARCH64-LINUX";
    };
    "x86_64-darwin" = {
      target = "x86_64-apple-darwin";
      sha256 = "sha256-PLACEHOLDER-FOR-X86_64-DARWIN";
    };
    "aarch64-darwin" = {
      target = "aarch64-apple-darwin";
      sha256 = "sha256-4abbcbPTZx9GOpM3eEBUOU8TDtpB2G+ttyCR+w+J38E=";
    };
  };

  currentPlatform =
    platformInfo.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");
in

stdenv.mkDerivation rec {
  pname = "codex-cli";
  version = "0.39.0";

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
