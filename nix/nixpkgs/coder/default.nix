{ pkgs, ... }:

let
  providerConfig = pkgs.writeTextFile {
    name = "herakles.json";
    text = builtins.toJSON {
      name = "herakles";
      engine = "openai";
      display_name = "herakles";
      description = "Herakles LLM Server";
      api_key_env = "HERAKLES_LLM_SERVER_API_KEY";
      base_url = "http://herakles.home:8000";
      models = [
        {
          name = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit";
          context_limit = 128000;
          input_token_cost = null;
          output_token_cost = null;
          currency = null;
          supports_cache_control = null;
        }
      ];
      headers = null;
      timeout_seconds = null;
      supports_streaming = true;
    };
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

  secrets = pkgs.callPackage ../secrets { };

  goose-cli-patched = pkgs.goose-cli.overrideAttrs (oldAttrs: {
    patches = (oldAttrs.patches or [ ]) ++ [ ./goose-prompt.patch ];
    postInstall = (oldAttrs.postInstall or "") + ''
      mv $out/bin/goose $out/bin/coder
    '';
  });
in
pkgs.writeShellScriptBin "coder" ''
  mkdir -p ~/.config/goose/custom_providers

  [ ! -f ~/.config/goose/custom_providers/herakles.json ] || \
    ! cmp -s ${providerConfig} ~/.config/goose/custom_providers/herakles.json && \
    cp -f ${providerConfig} ~/.config/goose/custom_providers/herakles.json && \
    chmod +w ~/.config/goose/custom_providers/herakles.json

  if ${secrets}/bin/secrets get EXA_API_KEY --optional >/dev/null 2>&1; then
    CONFIG_FILE=${gooseConfig}
    export EXA_API_KEY="$(${secrets}/bin/secrets get EXA_API_KEY)"
  else
    CONFIG_FILE=${gooseConfigExaDisabled}
  fi

  [ ! -f ~/.config/goose/config.yaml ] || \
    ! cmp -s "$CONFIG_FILE" ~/.config/goose/config.yaml && \
    cp -f "$CONFIG_FILE" ~/.config/goose/config.yaml && \
    chmod +w ~/.config/goose/config.yaml

  [ ! -f ~/.config/goose/.goosehints ] || \
    ! cmp -s ${gooseHints} ~/.config/goose/.goosehints && \
    cp -f ${gooseHints} ~/.config/goose/.goosehints && \
    chmod +w ~/.config/goose/.goosehints

  export GOOSE_DISABLE_KEYRING=1
  export GOOSE_PROVIDER="herakles"
  export GOOSE_MODEL="cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit"
  export HERAKLES_LLM_SERVER_API_KEY="dummy"

  exec ${goose-cli-patched}/bin/coder "$@"
''
