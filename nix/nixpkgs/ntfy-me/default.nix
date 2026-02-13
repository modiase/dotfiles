{
  writeShellApplication,
  symlinkJoin,
  coreutils,
  curl,
  google-cloud-sdk,
  jq,
  secrets,
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

  ding = writeShellApplication {
    name = "ding";
    runtimeInputs = [
      coreutils
      ntfy-me
    ];
    text = builtins.readFile ./ding.sh;
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
    ding
    ntfy-listen
  ];
}
