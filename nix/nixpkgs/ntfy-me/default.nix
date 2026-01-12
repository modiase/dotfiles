{
  lib,
  stdenv,
  writeShellApplication,
  symlinkJoin,
  callPackage,
  runCommand,
  imagemagick,
  curl,
  httpie,
  jq,
  secrets,
}:

let
  colors = import ../../colors.nix;
  swiftdialog = callPackage ../swiftdialog { };

  ding-background =
    runCommand "ding-background"
      {
        nativeBuildInputs = [ imagemagick ];
      }
      ''
        mkdir -p $out
        magick -size 500x350 \
          xc:'#${colors.background}' \
          \( -size 500x350 gradient:'#ffffff'-'#000000' -alpha set -channel A -evaluate set 5% \) \
          -compose over -composite \
          $out/background.png
      '';

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
    text = builtins.replaceStrings [ "@DING_BACKGROUND@" ] [ "${ding-background}/background.png" ] (
      builtins.readFile ./ding.sh
    );
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
