{ pkgs, ... }:

let
  providerConfig = pkgs.writeTextFile {
    name = "custom_herakles.json";
    text = builtins.readFile ./config/custom_herakles.json;
  };

  gooseConfig = pkgs.writeTextFile {
    name = "config.yaml";
    text = builtins.readFile ./config/config.yaml;
  };
in
pkgs.writeShellScriptBin "coder" ''
  mkdir -p ~/.config/goose/custom_providers

  [ ! -f ~/.config/goose/custom_providers/custom_herakles.json ] || \
    ! cmp -s ${providerConfig} ~/.config/goose/custom_providers/custom_herakles.json && \
    cp ${providerConfig} ~/.config/goose/custom_providers/custom_herakles.json

  [ ! -f ~/.config/goose/config.yaml ] || \
    ! cmp -s ${gooseConfig} ~/.config/goose/config.yaml && \
    cp ${gooseConfig} ~/.config/goose/config.yaml

  export GOOSE_DISABLE_KEYRING=1
  export GOOSE_PROVIDER="custom_herakles"
  export GOOSE_MODEL="cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit"
  export CUSTOM_HERAKLES_API_KEY="dummy"

  exec ${pkgs.goose-cli}/bin/goose "$@"
''
