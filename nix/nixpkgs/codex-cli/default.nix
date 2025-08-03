{
  pkgs,
  lib,
  fetchFromGitHub,
  rustPlatform,
}:

rustPlatform.buildRustPackage rec {
  pname = "codex-cli";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "81bb1c9e264095708a01f6326bf8d527a6b2d47b";
    sha256 = "sha256-WKf4C7H7Dn4Jt0ygeBxVoTW8kDni5igs/CiKMW2JlpY=";
  };

  sourceRoot = "${src.name}/codex-rs";
  cargoHash = "sha256-SNl6UXzvtVR+ep7CIoCcpvET8Hs7ew1fmHqOXbzN7kU=";

  nativeBuildInputs = with pkgs; [
    pkg-config
  ];

  buildInputs =
    with pkgs;
    [
      openssl
    ]
    ++ lib.optionals stdenv.isDarwin [
      darwin.apple_sdk.frameworks.Security
      darwin.apple_sdk.frameworks.SystemConfiguration
    ];

  cargoBuildFlags = [
    "--bin"
    "codex"
  ];
  doCheck = false;

  meta = with lib; {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    license = licenses.asl20;
    maintainers = [ ];
    platforms = platforms.unix;
    mainProgram = "codex";
  };
}
