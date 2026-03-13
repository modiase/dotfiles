{
  callPackage,
  writeShellApplication,
  symlinkJoin,
  coreutils,
  curl,
  google-cloud-sdk,
  jq,
  secrets,
  ding,
}:

let
  devlogsLib = callPackage ../devlogs-lib { };

  ntfy-me = writeShellApplication {
    name = "ntfy-me";
    runtimeInputs = [
      google-cloud-sdk
      jq
    ];
    text = builtins.readFile ./ntfy-me.sh;
  };

  ntfy-listen = writeShellApplication {
    name = "ntfy-listen";
    runtimeInputs = [
      # keep-sorted start
      coreutils
      curl
      ding
      jq
      secrets
      # keep-sorted end
    ];
    text = ''
      export DEVLOGS_COMPONENT="ntfy-listen"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
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
