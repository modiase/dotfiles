{
  config,
  pkgs,
  lib,
  rootDomain,
  ...
}:

let
  ports = import ../ports.nix;
  autheliaConfigDir = "/var/lib/authelia";

  oauthClientSecret = "$$pbkdf2-sha512$$310000$$2.TmHnVSrVKf.bMmKMuwTA$$/./4TGbhzQ17QKwtLmEYKgEldPfrrsfc2a6I1euPy7vZllqG.K2NCf.0Ha5EtvIAfgjgBr4wjMXbaNAKSC4uiA";

  mkOAuthClient = serviceName: {
    client_id = "${serviceName}-client";
    client_secret = oauthClientSecret;
    public = false;
    authorization_policy = "one_factor";
    scopes = [ "authelia.bearer.authz" ];
    audience = [ "https://${serviceName}.${rootDomain}" ];
    grant_types = [ "client_credentials" ];
    token_endpoint_auth_method = "client_secret_basic";
  };

  autheliaConfig = {
    theme = "dark";

    identity_validation = {
      reset_password = {
        jwt_secret = "\${JWT_SECRET}";
      };
    };

    server = {
      address = "tcp://127.0.0.1:${toString ports.authelia}";
      endpoints = {
        authz = {
          auth-request = {
            implementation = "AuthRequest";
            authn_strategies = [
              {
                name = "HeaderAuthorization";
                schemes = [
                  "Basic"
                  "Bearer"
                ];
              }
              {
                name = "CookieSession";
              }
            ];
          };
        };
      };
    };

    log = {
      level = "info";
      format = "text";
    };

    authentication_backend = {
      file = {
        path = "${autheliaConfigDir}/users_database.yml";
        password = {
          algorithm = "argon2";
          argon2 = {
            variant = "argon2id";
            iterations = 3;
            memory = 65536;
            parallelism = 4;
            key_length = 32;
            salt_length = 16;
          };
        };
      };
    };

    session = {
      secret = "\${SESSION_SECRET}";
      cookies = [
        {
          domain = rootDomain;
          authelia_url = "https://auth.${rootDomain}";
        }
      ];
      expiration = "1h";
      inactivity = "5m";
      remember_me = "1M";

      redis = {
        host = "127.0.0.1";
        port = ports.redis;
        database_index = 0;
      };
    };

    storage = {
      encryption_key = "\${STORAGE_KEY}";
      local = {
        path = "${autheliaConfigDir}/db.sqlite3";
      };
    };

    notifier = {
      disable_startup_check = true;
      filesystem = {
        filename = "${autheliaConfigDir}/notification.txt";
      };
    };

    access_control = {
      default_policy = "deny";
      rules = [
        {
          domain = [ "auth.${rootDomain}" ];
          policy = "bypass";
        }
        {
          domain = [ "hermes.${rootDomain}" ];
          policy = "one_factor";
        }
        {
          domain = [ "tmp.${rootDomain}" ];
          policy = "one_factor";
        }
        {
          domain = [ "n8n.${rootDomain}" ];
          policy = "one_factor";
          subject = [ "oauth2:client:n8n-client" ];
        }
        {
          domain = [ "n8n.${rootDomain}" ];
          policy = "one_factor";
        }
      ];
    };

    identity_providers = {
      oidc = {
        hmac_secret = "\${HMAC_SECRET}";
        jwks = [
          {
            algorithm = "RS256";
            key = "\${JWKS_KEY}";
          }
        ];
        clients = map mkOAuthClient [
          "n8n"
        ];
      };
    };

    regulation = {
      max_retries = 3;
      find_time = "2m";
      ban_time = "5m";
    };
  };

  userDatabase = ''
    users:
      moye:
        displayname: "Moye"
        password: "$argon2id$v=19$m=65536,t=3,p=4$c4tZWvrNgz08yqJyw8xi4w$s32XYBg7vb0p8qvHufJb6LTOyZsauShPEfb8heyiGaw"
        email: moyeodiase@gmail.com
        groups:
          - admins
          - dev
  '';

in
{
  services.redis.servers.authelia = {
    enable = true;
    port = ports.redis;
  };

  environment.etc."authelia/configuration.template.yml".text =
    let
      jsonConfig = builtins.toJSON autheliaConfig;
      yamlConfig = pkgs.runCommand "authelia-yaml" { buildInputs = [ pkgs.yq ]; } ''
        echo '${jsonConfig}' | yq -y . > $out
      '';
    in
    builtins.readFile yamlConfig;

  environment.etc."authelia/users_database.yml".text = userDatabase;

  systemd.services.fetch-authelia-secrets = {
    wantedBy = [ "authelia.service" ];
    before = [ "authelia.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      mkdir -p /etc/authelia

      export JWT_SECRET=$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="authelia-secrets" --project="modiase-infra" | grep AUTHELIA_JWT_SECRET | cut -d= -f2)
      export SESSION_SECRET=$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="authelia-secrets" --project="modiase-infra" | grep AUTHELIA_SESSION_SECRET | cut -d= -f2)
      export STORAGE_KEY=$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="authelia-secrets" --project="modiase-infra" | grep AUTHELIA_STORAGE_ENCRYPTION_KEY | cut -d= -f2)
      export HMAC_SECRET=$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="authelia-hmac-secret" --project="modiase-infra")
      export JWKS_KEY=$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="authelia-oidc-jwks-key" --project="modiase-infra")

      ${pkgs.envsubst}/bin/envsubst < /etc/authelia/configuration.template.yml > /tmp/authelia-config-raw.yml

      ${pkgs.gawk}/bin/awk '
        /key: -----BEGIN/ {
          print "        key: |"
          sub(/.*key: /, "")
          print "          " $0
          in_key = 1
          next
        }
        in_key && /-----END/ {
          print "          " $0
          in_key = 0
          next
        }
        in_key {
          print "          " $0
          next
        }
        { print }
      ' /tmp/authelia-config-raw.yml > /etc/authelia/configuration.yml

      chown authelia:authelia /etc/authelia/configuration.yml
      chmod 600 /etc/authelia/configuration.yml
    '';
  };

  systemd.services.authelia = {
    description = "Authelia authentication and authorization server";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "redis-authelia.service"
      "fetch-authelia-secrets.service"
    ];
    wants = [ "network-online.target" ];
    requires = [
      "redis-authelia.service"
      "fetch-authelia-secrets.service"
    ];

    serviceConfig = {
      Type = "simple";
      User = "authelia";
      Group = "authelia";
      ExecStart = "${pkgs.authelia}/bin/authelia --config /etc/authelia/configuration.yml";
      Restart = "always";
      RestartSec = "5s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ autheliaConfigDir ];
      ReadOnlyPaths = [ "/etc/authelia" ];
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectHostname = true;
      ProtectClock = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      RemoveIPC = true;
    };

    preStart = ''
      mkdir -p ${autheliaConfigDir}
      chown authelia:authelia ${autheliaConfigDir}
      chmod 700 ${autheliaConfigDir}

      if [ ! -f ${autheliaConfigDir}/users_database.yml ]; then
        cp /etc/authelia/users_database.yml ${autheliaConfigDir}/users_database.yml
        chown authelia:authelia ${autheliaConfigDir}/users_database.yml
        chmod 600 ${autheliaConfigDir}/users_database.yml
      fi
    '';
  };

  users.users.authelia = {
    description = "Authelia daemon user";
    isSystemUser = true;
    group = "authelia";
    home = autheliaConfigDir;
    createHome = true;
  };

  users.groups.authelia = { };

}
