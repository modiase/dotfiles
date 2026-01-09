{
  lib,
  stdenv,
  writeShellApplication,
  symlinkJoin,
  callPackage,
  curl,
  httpie,
  jq,
  secrets,
}:

let
  swiftdialog = callPackage ../swiftdialog { };

  ntfy-me = writeShellApplication {
    name = "ntfy-me";
    runtimeInputs = [
      secrets
      httpie
      jq
    ];
    text = builtins.readFile ./ntfy-me.sh;
  };

  ding = writeShellApplication {
    name = "ding";
    runtimeInputs = [ ntfy-me ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ swiftdialog ];
    text = builtins.readFile ./ding.sh;
  };

  ntfy-listen = writeShellApplication {
    name = "ntfy-listen";
    runtimeInputs = [
      secrets
      curl
      jq
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
