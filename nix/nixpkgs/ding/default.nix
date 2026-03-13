{
  callPackage,
  writeShellApplication,
  coreutils,
}:
let
  devlogsLib = callPackage ../devlogs-lib { };
in
writeShellApplication {
  name = "ding";
  runtimeInputs = [ coreutils ];
  text = ''
    export DEVLOGS_COMPONENT="ding"
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    ${builtins.readFile ./ding.sh}
  '';
}
