{ config, pkgs, ... }:

{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.modiase.dev";
      listen-http = ":8080";
      cache-file = "/var/lib/ntfy/cache.db";
      attachment-cache-dir = "/var/lib/ntfy/attachments";
      behind-proxy = true;
      upstream-base-url = "https://ntfy.sh";
    };
  };

  systemd.services.ntfy-sh = {
    preStart = ''
      mkdir -p /var/lib/ntfy/attachments
      chown -R ntfy-sh:ntfy-sh /var/lib/ntfy
      chmod 755 /var/lib/ntfy
    '';
  };
}
