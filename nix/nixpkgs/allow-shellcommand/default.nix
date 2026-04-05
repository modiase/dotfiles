{
  pkgs,
  lib,
  denyRulesJson,
  ...
}:

let
  combinedSrc = pkgs.runCommand "allow-shellcommand-src" { } ''
    mkdir -p $out/allow-shellcommand $out/devlogs-lib
    cp -r ${./.}/* $out/allow-shellcommand/
    cp -r ${../devlogs-lib}/* $out/devlogs-lib/
    chmod +w $out/allow-shellcommand/deny-rules.json
    cp ${denyRulesJson} $out/allow-shellcommand/deny-rules.json
  '';
in
pkgs.buildGoModule {
  pname = "allow-shellcommand";
  version = "1.0.0";

  src = combinedSrc;
  sourceRoot = "${combinedSrc.name}/allow-shellcommand";

  vendorHash = null;

  meta = with lib; {
    description = "Claude Code hook to auto-approve shell commands with redirects";
    mainProgram = "allow-shellcommand";
  };
}
