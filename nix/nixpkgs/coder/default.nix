{ pkgs, ... }:

let
  opencodeConfig = pkgs.writeTextFile {
    name = "opencode.json";
    text = builtins.readFile ./config/opencode.json;
  };

  # SDK requires an API key even though herakles doesn't validate it
  authConfig = pkgs.writeTextFile {
    name = "auth.json";
    text = builtins.toJSON {
      herakles = {
        type = "api";
        key = "not-needed";
      };
    };
  };
in
pkgs.writeShellScriptBin "code" ''
  mkdir -p ~/.config/opencode
  mkdir -p ~/.local/share/opencode

  [ ! -f ~/.config/opencode/opencode.json ] || \
    ! cmp -s ${opencodeConfig} ~/.config/opencode/opencode.json && \
    cp -f ${opencodeConfig} ~/.config/opencode/opencode.json && \
    chmod +w ~/.config/opencode/opencode.json

  [ ! -f ~/.local/share/opencode/auth.json ] || \
    ! cmp -s ${authConfig} ~/.local/share/opencode/auth.json && \
    cp -f ${authConfig} ~/.local/share/opencode/auth.json && \
    chmod +w ~/.local/share/opencode/auth.json

  exec ${pkgs.opencode}/bin/opencode "$@"
''
