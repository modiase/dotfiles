{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "agents-plan-responder";
  version = "0.1.0";

  src = ./.;

  vendorHash = "sha256-/Bl4G5STa5lnNntZnMmt+BfES+N7ZYAwC9tzpuqUKcc=";

  meta = with lib; {
    description = "Background process that bridges FIFO responses to tmux panes for plan review";
    license = licenses.mit;
    maintainers = [ ];
  };
}
