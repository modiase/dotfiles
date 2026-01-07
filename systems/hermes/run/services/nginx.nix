{
  config,
  pkgs,
  rootDomain,
  ...
}:

let
  ports = import ../ports.nix;
  commonVhostConfig = {
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
    addSSL = true;
    sslCertificate = "/etc/ssl/certs/cloudflare-origin.pem";
    sslCertificateKey = "/etc/ssl/private/cloudflare-origin.key";
  };

  commonProxyConfig = ''
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Port $server_port;
  '';

  autheliaAuthConfig = ''
    auth_request /internal/authelia/authz;
    auth_request_set $user $upstream_http_remote_user;
    auth_request_set $groups $upstream_http_remote_groups;
    auth_request_set $name $upstream_http_remote_name;
    auth_request_set $email $upstream_http_remote_email;
    auth_request_set $redirection_url $upstream_http_location;

    proxy_set_header Remote-User $user;
    proxy_set_header Remote-Groups $groups;
    proxy_set_header Remote-Name $name;
    proxy_set_header Remote-Email $email;
    proxy_set_header Authorization "";

    error_page 401 =302 $redirection_url;
  '';

  protectedProxyConfig = commonProxyConfig + autheliaAuthConfig;

  autheliaEndpointConfig = {
    proxyPass = "http://127.0.0.1:${toString ports.authelia}/api/authz/auth-request";
    extraConfig = ''
      internal;
      proxy_pass_request_body off;
      proxy_set_header Content-Length "";
      proxy_set_header Connection "";
      proxy_set_header X-Original-Method $request_method;
      proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header Authorization $http_authorization;
      proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;
      proxy_redirect http:// $scheme://;
      proxy_http_version 1.1;
      proxy_cache_bypass $cookie_session;
      proxy_no_cache $cookie_session;
      proxy_buffers 4 32k;
      client_body_buffer_size 128k;
      send_timeout 5m;
      proxy_read_timeout 240;
      proxy_send_timeout 240;
      proxy_connect_timeout 240;
    '';
  };

  cloudflareIPv4 = [
    "103.21.244.0/22"
    "103.22.200.0/22"
    "103.31.4.0/22"
    "104.16.0.0/13"
    "104.24.0.0/14"
    "108.162.192.0/18"
    "131.0.72.0/22"
    "141.101.64.0/18"
    "162.158.0.0/15"
    "172.64.0.0/13"
    "173.245.48.0/20"
    "188.114.96.0/20"
    "190.93.240.0/20"
    "197.234.240.0/22"
    "198.41.128.0/17"
  ];

  cloudflareIPv6 = [
    "2400:cb00::/32"
    "2405:8100::/32"
    "2405:b500::/32"
    "2606:4700::/32"
    "2803:f800::/32"
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

      add_header X-Frame-Options "SAMEORIGIN" always;
      add_header X-Content-Type-Options "nosniff" always;
      add_header X-XSS-Protection "1; mode=block" always;
      add_header Referrer-Policy "strict-origin-when-cross-origin" always;
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

      proxy_headers_hash_max_size 1024;
      proxy_headers_hash_bucket_size 128;

      ${setRealIpLines}
      real_ip_header CF-Connecting-IP;
      real_ip_recursive on;

    '';

    virtualHosts."auth.${rootDomain}" = commonVhostConfig // {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString ports.authelia}/";
        proxyWebsockets = true;
        extraConfig = commonProxyConfig;
      };
      locations."/internal/authelia/authz" = autheliaEndpointConfig;
    };

    virtualHosts."n8n.${rootDomain}" = commonVhostConfig // {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString ports.n8n}/";
        proxyWebsockets = true;
        extraConfig = protectedProxyConfig + ''
          proxy_set_header Remote-User $email;
        '';
      };
      locations."/webhook/rest/oauth2-credential/callback" = {
        proxyPass = "http://127.0.0.1:${toString ports.n8n}/webhook/rest/oauth2-credential/callback";
        extraConfig = commonProxyConfig;
      };
      locations."/internal/authelia/authz" = autheliaEndpointConfig;
    };

    virtualHosts."ntfy.${rootDomain}" = commonVhostConfig // {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString ports.ntfy}/";
        proxyWebsockets = true;
        extraConfig = commonProxyConfig + ''
          proxy_buffering off;
          proxy_request_buffering off;
          proxy_read_timeout 300;

          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
        '';
      };
    };

    virtualHosts."tmp.${rootDomain}" = commonVhostConfig // {
      locations."/" = {
        proxyPass = "http://127.0.0.1:8888/";
        proxyWebsockets = true;
        extraConfig = protectedProxyConfig;
      };
      locations."/internal/authelia/authz" = autheliaEndpointConfig;
    };

    virtualHosts."hermes.${rootDomain}" = commonVhostConfig // {
      root = pkgs.runCommand "hermes-static" { } ''
        mkdir -p $out
        cp ${../../static}/* $out/
      '';
      locations."/internal/authelia/authz" = autheliaEndpointConfig;
      locations."/" = {
        extraConfig = autheliaAuthConfig;
      };
    };
  };
}
