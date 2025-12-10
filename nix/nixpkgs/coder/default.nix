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

  gooseConfigExaDisabled = pkgs.writeTextFile {
    name = "config-exa-disabled.yaml";
    text = builtins.replaceStrings [ "exa:\n  enabled: true" ] [ "exa:\n  enabled: false" ] (
      builtins.readFile ./config/config.yaml
    );
  };

  gooseHints = pkgs.writeTextFile {
    name = ".goosehints";
    text = builtins.readFile ./config/.goosehints;
  };

  secretsmanager = pkgs.callPackage ../secretsmanager { };

  goose-cli-patched = pkgs.goose-cli.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./goose-prompt.patch ];
  });
in
pkgs.writeShellScriptBin "coder" ''
  mkdir -p ~/.config/goose/custom_providers

  [ ! -f ~/.config/goose/custom_providers/custom_herakles.json ] || \
    ! cmp -s ${providerConfig} ~/.config/goose/custom_providers/custom_herakles.json && \
    cp ${providerConfig} ~/.config/goose/custom_providers/custom_herakles.json

  if ${secretsmanager}/bin/secretsmanager get EXA_API_KEY --optional >/dev/null 2>&1; then
    CONFIG_FILE=${gooseConfig}
  else
    CONFIG_FILE=${gooseConfigExaDisabled}
  fi

  [ ! -f ~/.config/goose/config.yaml ] || \
    ! cmp -s "$CONFIG_FILE" ~/.config/goose/config.yaml && \
    cp "$CONFIG_FILE" ~/.config/goose/config.yaml

  [ ! -f ~/.config/goose/.goosehints ] || \
    ! cmp -s ${gooseHints} ~/.config/goose/.goosehints && \
    cp ${gooseHints} ~/.config/goose/.goosehints

  export GOOSE_DISABLE_KEYRING=1
  export GOOSE_PROVIDER="custom_herakles"
  export GOOSE_MODEL="cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit"
  export CUSTOM_HERAKLES_API_KEY="dummy"

  exec ${goose-cli-patched}/bin/goose "$@"
''
