{
  pkgs,
  lib ? pkgs.lib,
}:
let
  settings = import ./settings.nix;
  settingsJson = pkgs.writeText "claude-settings.json" (builtins.toJSON settings);
  claudeMd = ./CLAUDE.md;
in
pkgs.writeShellApplication {
  name = "claude";
  runtimeInputs = [ pkgs.claude-code ];
  text = ''
    runtime_dir="''${XDG_RUNTIME_DIR:-/tmp}"
    config_dir="''${CLAUDE_CONFIG_DIR:-$runtime_dir/claude-nix}"
    export CLAUDE_CONFIG_DIR="$config_dir"

    mkdir -p "$config_dir"

    settings_file="$config_dir/settings.json"
    if [[ ! -e "$settings_file" ]] || [[ -L "$settings_file" ]]; then
      ln -sf "${settingsJson}" "$settings_file"
    fi

    claude_md="$config_dir/CLAUDE.md"
    if [[ ! -e "$claude_md" ]] || [[ -L "$claude_md" ]]; then
      ln -sf "${claudeMd}" "$claude_md"
    fi

    exec claude "$@"
  '';
}
