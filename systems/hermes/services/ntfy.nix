{ config, pkgs, ... }:

{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.modiase.dev";
      listen-http = ":8080";
      cache-file = "/var/lib/ntfy/cache.db";
      attachment-cache-dir = "/var/lib/ntfy/attachments";
      auth-file = "/var/lib/ntfy/user.db";
      auth-default-access = "deny-all";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ntfy 0750 ntfy-sh ntfy-sh -"
    "d /var/lib/ntfy/attachments 0750 ntfy-sh ntfy-sh -"
  ];
}
