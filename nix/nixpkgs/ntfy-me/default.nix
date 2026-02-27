{
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
      coreutils
      curl
      jq
      secrets
      ding
    ];
    text = builtins.readFile ./ntfy-listen.sh;
  };
in
symlinkJoin {
  name = "ntfy-me";
  paths = [
    ntfy-me
    ntfy-listen
  ];
}
