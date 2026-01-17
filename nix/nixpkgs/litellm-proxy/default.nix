{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.litellm-proxy;
  pythonEnv = pkgs.python312.withPackages (
    ps: with ps; [
      litellm
      apscheduler
      backoff
      cryptography
      email-validator
      fastapi
      fastapi-sso
      gunicorn
      orjson
      pyjwt
      python-multipart
      pyyaml
      uvicorn
      uvloop
      httpx
      aiohttp
    ]
  );
  configFile = pkgs.writeText "litellm_config.yaml" (builtins.toJSON cfg.settings);
in
with lib;
{
  options.services.litellm-proxy = {
    enable = mkEnableOption "LiteLLM Proxy";

    port = mkOption {
      type = types.port;
      default = 4000;
      description = "Port for LiteLLM proxy";
    };

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Host/IP to bind to";
    };

    settings = mkOption {
      type = types.attrs;
      default = { };
      description = "LiteLLM configuration (converted to YAML)";
    };

    environmentFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to environment file with API keys";
    };
  };

  config = mkIf cfg.enable {
    systemd.services.litellm-proxy = {
      description = "LiteLLM Proxy Server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${pythonEnv}/bin/litellm --config ${configFile} --host ${cfg.host} --port ${toString cfg.port}";
        Restart = "always";
        RestartSec = "10s";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      }
      // lib.optionalAttrs (cfg.environmentFile != null) {
        EnvironmentFile = cfg.environmentFile;
      };
    };
  };
}
