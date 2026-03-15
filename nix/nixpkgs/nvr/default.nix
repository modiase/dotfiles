{
  callPackage,
  writeShellApplication,
  neovim-remote,
}:
let
  devlogsLib = callPackage ../devlogs-lib { };
in
writeShellApplication {
  name = "nvr";
  text = ''
    export DEVLOGS_COMPONENT="nvr"
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    clog debug "nvr $*"
    exec ${neovim-remote}/bin/nvr "$@"
  '';
}
