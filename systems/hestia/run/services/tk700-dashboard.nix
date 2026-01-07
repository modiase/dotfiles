{
  config,
  pkgs,
  lib,
  ...
}:

{
  systemd.services.tk700-controller-dashboard = {
    description = "BenQ TK700 Controller Dashboard";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      TK700_CONTROLLER_HOST = "192.168.1.80";
      TK700_CONTROLLER_PORT = "8234";
      TK700_CONTROLLER_TIMEOUT = "5000";
      PORT = "3000";
      NODE_ENV = "production";
      BUN_INSTALL_CACHE_DIR = "/var/cache/tk700-controller-dashboard/bun";
    };

    serviceConfig = {
      Type = "simple";
      User = "tk700-controller-dashboard";
      Group = "tk700-controller-dashboard";
      Restart = "on-failure";
      RestartSec = "5s";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;

      CacheDirectory = "tk700-controller-dashboard/bun";

      MemoryMax = "512M";
      CPUQuota = "50%";

      ExecStart = "${pkgs.tk700-controller-dashboard}/bin/tk700-controller-dashboard-server";
    };
  };

  users.users.tk700-controller-dashboard = {
    isSystemUser = true;
    group = "tk700-controller-dashboard";
    description = "TK700 Controller Dashboard Service User";
  };

  users.groups.tk700-controller-dashboard = { };
}
