{
  config,
  pkgs,
  lib,
  ...
}:

let
  ports = {
    homeAssistant = 8123;
    tk700Dashboard = 3000;
  };
in

{
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."hestia.local" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
      ];

      locations."= /" = {
        return = "301 /hass/";
      };

      locations."/auth/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/auth/";
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
        '';
      };

      locations."/api/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/api/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
          proxy_set_header Upgrade ''$http_upgrade;
          proxy_set_header Connection ''$connection_upgrade;
        '';
      };

      locations."/frontend_latest/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/frontend_latest/";
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_cache_valid 200 1d;
          add_header Cache-Control "public, max-age=86400";
        '';
      };

      locations."/static/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/static/";
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_cache_valid 200 1d;
          add_header Cache-Control "public, max-age=86400";
        '';
      };

      locations."/local/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/local/";
        extraConfig = ''
          proxy_set_header Host ''$host;
        '';
      };

      locations."/hacsfiles/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/hacsfiles/";
        extraConfig = ''
          proxy_set_header Host ''$host;
        '';
      };

      locations."/lovelace/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/lovelace/";
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
        '';
      };

      locations."/hass/" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
          proxy_set_header Upgrade ''$http_upgrade;
          proxy_set_header Connection ''$connection_upgrade;

          proxy_redirect http:// /hass/;

          proxy_read_timeout 90;
          proxy_buffering off;
        '';
      };

      locations."/hass/api" = {
        proxyPass = "http://127.0.0.1:${toString ports.homeAssistant}/api";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
        '';
      };

      locations."/projector/" = {
        proxyPass = "http://127.0.0.1:${toString ports.tk700Dashboard}/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host ''$host;
          proxy_set_header X-Real-IP ''$remote_addr;
          proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ''$scheme;
          proxy_set_header Upgrade ''$http_upgrade;
          proxy_set_header Connection ''$connection_upgrade;

          proxy_redirect / /projector/;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];
}
