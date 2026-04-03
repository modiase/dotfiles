{
  callPackage,
  writeShellApplication,
  coreutils,
  tmux,
}:
let
  devlogsLib = callPackage ../devlogs-lib { };
in
writeShellApplication {
  name = "attn";
  runtimeInputs = [
    coreutils
    tmux
  ];
  text = ''
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init attn
    ${builtins.readFile ./attn.sh}
  '';
  meta.description = "Terminal notification tool that adapts to context (macOS/Linux, SSH, tmux, focus state)";
}
