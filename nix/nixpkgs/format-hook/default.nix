{
  pkgs,
  name ? "format-hook",
  script ? ./format-hook.sh,
  extraRuntimeInputs ? [ ],
}:
let
  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  defaultRuntimeInputs = [
    pkgs.biome
    pkgs.buildifier
    pkgs.fish
    pkgs.go
    pkgs.google-java-format
    pkgs.jq
    pkgs.nixfmt-rfc-style
    pkgs.prettier
    pkgs.opentofu
    pkgs.ruff
    pkgs.rustfmt
    pkgs.shfmt
    pkgs.statix
    pkgs.stylua
  ];
in
pkgs.writeShellApplication {
  inherit name;
  runtimeInputs = defaultRuntimeInputs ++ extraRuntimeInputs;
  text = ''
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init ${name}
    ${builtins.readFile script}
  '';
}
