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
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init nvr
    clog debug "nvr $*"
    exec ${neovim-remote}/bin/nvr "$@"
  '';
}
