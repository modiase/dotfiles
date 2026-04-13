{
  pkgs,
  name ? "format-hook",
  extraRuntimeInputs ? [ ],
}:
let
  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  formatRuntimeInputs = [
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
  ]
  ++ extraRuntimeInputs;

  devlogsInit = name': ''
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    devlogs_init ${name'}
  '';

  formatFileSrc = builtins.readFile ./format-file.sh;

  formatHook = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = formatRuntimeInputs;
    text = ''
      ${devlogsInit name}
      ${formatFileSrc}
      ${builtins.readFile ./format-hook.sh}
    '';
  };

  recordEdit = pkgs.writeShellApplication {
    name = "${name}-record";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      ${devlogsInit "${name}-record"}
      ${builtins.readFile ./record-edit.sh}
    '';
  };

  formatStop = pkgs.writeShellApplication {
    name = "${name}-stop";
    runtimeInputs = formatRuntimeInputs;
    text = ''
      ${devlogsInit "${name}-stop"}
      ${formatFileSrc}
      ${builtins.readFile ./format-stop.sh}
    '';
  };
in
formatHook
// {
  passthru = {
    inherit recordEdit formatStop;
  };
}
