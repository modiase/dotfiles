{
  config,
  pkgs,
  lib,
  ...
}:

{
  systemd.services.tk700-dashboard = {
    description = "BenQ TK700 Control Dashboard";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      TK700_HOST = "192.168.1.80";
      TK700_PORT = "8234";
      TK700_TIMEOUT = "5000";
      PORT = "3000";
      NODE_ENV = "production";
      BUN_INSTALL_CACHE_DIR = "/var/cache/tk700-dashboard/bun";
    };

    serviceConfig = {
      Type = "simple";
      User = "tk700-dashboard";
      Group = "tk700-dashboard";
      Restart = "on-failure";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;

      CacheDirectory = "tk700-dashboard/bun";

      MemoryMax = "512M";
      CPUQuota = "50%";

      ExecStart = "${pkgs.tk700-control-dashboard}/bin/benq-control-server";
    };
  };

  users.users.tk700-dashboard = {
    isSystemUser = true;
    group = "tk700-dashboard";
    description = "TK700 Dashboard Service User";
  };

  users.groups.tk700-dashboard = { };
}
