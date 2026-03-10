{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "gemini-nvim-ide-bridge";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-/Bl4G5STa5lnNntZnMmt+BfES+N7ZYAwC9tzpuqUKcc=";

  meta = with lib; {
    description = "A bridge between Gemini CLI IDE protocol and Neovim RPC";
    license = licenses.mit;
    maintainers = [ ];
  };
}
