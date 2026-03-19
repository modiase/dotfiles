{ pkgs, lib, ... }:

let
  combinedSrc = pkgs.runCommand "agents-plan-responder-src" { } ''
    mkdir -p $out/agents-plan-responder $out/devlogs-lib
    cp -r ${./.}/* $out/agents-plan-responder/
    cp -r ${../devlogs-lib}/* $out/devlogs-lib/
  '';
in
pkgs.buildGoModule {
  pname = "agents-plan-responder";
  version = "0.1.0";

  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/agents-plan-responder";

  vendorHash = null;

  meta = with lib; {
    description = "Background process that bridges FIFO responses to tmux panes for plan review";
    license = licenses.mit;
    maintainers = [ ];
  };
}
