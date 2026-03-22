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
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init ding
    ${builtins.readFile ./ding.sh}
  '';
}
