{
  config,
  pkgs,
  lib,
  rootDomain,
  ...
}:

let
  ports = import ../ports.nix;
  bucketName =
    let
      bucket = builtins.getEnv "HERMES_GCS_BUCKET";
    in
    if bucket != "" then bucket else (config.environment.variables.HERMES_GCS_BUCKET or "");
  rcloneFlags = "--config /etc/rclone/rclone.conf --fast-list --transfers=4 --checkers=8 --gcs-no-check-bucket";
  rcloneConf = ''
    [gcs]
    type = gcs
    env_auth = true
    bucket_policy_only = true
  '';
in

{
  environment.etc."rclone/rclone.conf".text = rcloneConf;
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${rootDomain}";
      listen-http = ":${toString ports.ntfy}";
      behind-proxy = true;
      # Required for iOS push notifications to work with self-hosted instances
      upstream-base-url = "https://ntfy.sh";

      auth-file = "/var/lib/ntfy-sh/user.db";
      auth-default-access = "deny-all";
    };
  };

  systemd.services.ntfy-restore = lib.mkIf (bucketName != "") {
    description = "Restore ntfy data from GCS";
    wantedBy = [ "multi-user.target" ];
    before = [ "ntfy-sh.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    path = [
      pkgs.rclone
      pkgs.coreutils
    ];

    script = ''
      set -euo pipefail
      ${pkgs.rclone}/bin/rclone ${rcloneFlags} ls gcs:${bucketName}/ntfy-sh >/dev/null 2>&1 && {
        ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync gcs:${bucketName}/ntfy-sh /var/lib/ntfy-sh
        chown -R ntfy-sh:ntfy-sh /var/lib/ntfy-sh
      } || true
    '';
  };

  systemd.services.ntfy-backup = lib.mkIf (bucketName != "") {
    description = "Backup ntfy data to GCS";
    after = [
      "network-online.target"
      "ntfy-restore.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    path = [
      pkgs.rclone
      pkgs.coreutils
    ];

    script = ''
      set -euo pipefail
      echo "Backing up ntfy-sh to gcs:${bucketName}/ntfy-sh ..."
      ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync /var/lib/ntfy-sh gcs:${bucketName}/ntfy-sh --delete-after
      echo "Backup completed"
    '';
  };

  systemd.timers.ntfy-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/1";
      Persistent = true;
      RandomizedDelaySec = "10s";
    };
  };
}
