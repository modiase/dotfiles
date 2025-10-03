{ config, pkgs, ... }:

let
  cloudflareIPv4 = [
    "173.245.48.0/20"
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "141.101.64.0/18"
    "108.162.192.0/18"
    "190.93.240.0/20"
    "188.114.96.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
    "162.158.0.0/15"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "172.64.0.0/13"
    "131.0.72.0/22"
  ];

  cloudflareIPv6 = [
    "2400:cb00::/32"
    "2606:4700::/32"
    "2803:f800::/32"
    "2405:b500::/32"
    "2405:8100::/32"
    "2a06:98c0::/29"
    "2c0f:f248::/32"
  ];

  setRealIpLines = builtins.concatStringsSep "\n" (
    map (ip: "set_real_ip_from " + ip + ";") (cloudflareIPv4 ++ cloudflareIPv6)
  );

in
{
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;

    commonHttpConfig = ''
      map $http_upgrade $connection_upgrade {
        default upgrade;
        ''' close;
      }

      ${setRealIpLines}
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;
    '';

    virtualHosts."n8n.modiase.dev" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
      ];
      enableACME = false;
      forceSSL = false;
      sslCertificate = "/etc/ssl/certs/cloudflare-origin.pem";
      sslCertificateKey = "/etc/ssl/private/cloudflare-origin.key";

      locations."/" = {
        proxyPass = "http://127.0.0.1:5678/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Port $server_port;
          proxy_redirect off;
        '';
      };
    };

    virtualHosts."ntfy.modiase.dev" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
      ];
      enableACME = false;
      forceSSL = false;
      sslCertificate = "/etc/ssl/certs/cloudflare-origin.pem";
      sslCertificateKey = "/etc/ssl/private/cloudflare-origin.key";

      locations."/" = {
        proxyPass = "http://127.0.0.1:8080/";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Port $server_port;
          proxy_redirect off;
          proxy_read_timeout 300;
        '';
      };
    };

    virtualHosts."hermes.modiase.dev" = {
      listen = [
        {
          addr = "0.0.0.0";
          port = 80;
        }
        {
          addr = "[::]";
          port = 80;
        }
        {
          addr = "0.0.0.0";
          port = 443;
          ssl = true;
        }
        {
          addr = "[::]";
          port = 443;
          ssl = true;
        }
      ];
      enableACME = false;
      forceSSL = false;
      sslCertificate = "/etc/ssl/certs/cloudflare-origin.pem";
      sslCertificateKey = "/etc/ssl/private/cloudflare-origin.key";
      root = pkgs.writeTextDir "index.html" ''
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Hermes</title>
        </head>
        <body>
            <h1>Hermes</h1>
            <p>Services available:</p>
            <ul>
                <li><a href="https://n8n.modiase.dev">n8n Workflow Automation</a></li>
                <li><a href="https://ntfy.modiase.dev">ntfy Notifications</a></li>
            </ul>
        </body>
        </html>
      '';
    };
  };
}
