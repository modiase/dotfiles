{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "gemini-editor-go";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-/Bl4G5STa5lnNntZnMmt+BfES+N7ZYAwC9tzpuqUKcc=";

  meta = with lib; {
    description = "External editor for Gemini CLI that opens files in Neovim via RPC";
    license = licenses.mit;
    maintainers = [ ];
  };
}
