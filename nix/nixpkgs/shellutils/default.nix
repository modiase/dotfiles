{
  writeTextFile,
  writeShellApplication,
  git,
  google-cloud-sdk,
  coreutils,
  cacert,
  openssh,
  nix,
}:

let
  hook-utils = writeTextFile {
    name = "hook-utils";
    destination = "/lib/hook-utils.sh";
    text = builtins.readFile ./hook-utils.sh;
    meta.description = "Exit hook utilities for bash scripts";
  };

  logging-utils = writeTextFile {
    name = "logging-utils";
    destination = "/lib/logging-utils.sh";
    meta.description = "Colour logging functions for bash scripts";
    text = ''
      source ${hook-utils}/lib/hook-utils.sh
      _DATE="${coreutils}/bin/date"
      _MKDIR="${coreutils}/bin/mkdir"
      _MKTEMP="${coreutils}/bin/mktemp"
      _CAT="${coreutils}/bin/cat"
      _TAIL="${coreutils}/bin/tail"
      ${builtins.readFile ./logging-utils.sh}
    '';
  };

  build-gce-nixos-image = writeShellApplication {
    name = "build-gce-nixos-image";
    meta.description = "Build NixOS images for Google Compute Engine";
    runtimeInputs = [
      # keep-sorted start
      cacert
      coreutils
      git
      google-cloud-sdk
      nix
      openssh
      # keep-sorted end
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${logging-utils}/lib/logging-utils.sh
      ${builtins.readFile ./build-gce-nixos-image.sh}
    '';
  };
in
{
  inherit hook-utils logging-utils build-gce-nixos-image;
}
