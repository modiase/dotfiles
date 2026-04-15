{
  callPackage,
  writeShellApplication,
  symlinkJoin,
  coreutils,
  curl,
  google-cloud-sdk,
  inetutils,
  jq,
  secrets,
  attn,
}:

let
  devlogsLib = callPackage ../devlogs-lib { };

  ntfy-me = writeShellApplication {
    name = "ntfy-me";
    runtimeInputs = [
      google-cloud-sdk
      inetutils
      jq
    ];
    text = builtins.readFile ./ntfy-me.sh;
  };

  ntfy-listen = writeShellApplication {
    name = "ntfy-listen";
    runtimeInputs = [
      # keep-sorted start
      attn
      coreutils
      curl
      inetutils
      jq
      secrets
      # keep-sorted end
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init ntfy-listen
      ${builtins.readFile ./ntfy-listen.sh}
    '';
  };
in
symlinkJoin {
  name = "ntfy-me";
  paths = [
    ntfy-me
    ntfy-listen
  ];
}
