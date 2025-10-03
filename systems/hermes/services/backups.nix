{
  config,
  pkgs,
  lib,
  ...
}:

let
  bucket = builtins.getEnv "HERMES_GCS_BUCKET";
  bucketName =
    if bucket != "" then bucket else (config.environment.variables.HERMES_GCS_BUCKET or "");
  rcloneConf = ''
    [gcs]
    type = gcs
    env_auth = true
  '';
in
{
  environment.etc."rclone/rclone.conf".text = rcloneConf;

  systemd.services.hermes-restore = lib.mkIf (bucketName != "") {
    description = "Restore ntfy and n8n data from GCS via rclone";
    wantedBy = [ "multi-user.target" ];
    before = [
      "hermes-backup.service"
      "ntfy-sh.service"
      "n8n.service"
    ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    path = [
      pkgs.rclone
      pkgs.coreutils
      pkgs.bash
      pkgs.rsync
    ];

    script = ''
      set -euo pipefail

      if ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf ls gcs:${bucketName}/ntfy >/dev/null 2>&1; then
        ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf \
          sync gcs:${bucketName}/ntfy /var/lib/ntfy --fast-list --transfers=4 --checkers=8
      fi

      if ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf ls gcs:${bucketName}/n8n >/dev/null 2>&1; then
        ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf \
          sync gcs:${bucketName}/n8n /var/lib/n8n --fast-list --transfers=4 --checkers=8
      fi
    '';
  };

  systemd.services.hermes-backup = {
    description = "Backup ntfy and n8n data to GCS via rclone";
    after = [
      "network-online.target"
      "hermes-restore.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };

    path = [
      pkgs.rclone
      pkgs.coreutils
      pkgs.bash
      pkgs.rsync
    ];

    script = lib.mkIf (bucketName != "") ''
      set -euo pipefail

      echo "Backing up ntfy to gcs:${bucketName}/ntfy ..."
      ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf \
        sync /var/lib/ntfy gcs:${bucketName}/ntfy \
        --fast-list --transfers=4 --checkers=8 --delete-after

      echo "Backing up n8n to gcs:${bucketName}/n8n ..."
      ${pkgs.rclone}/bin/rclone --config /etc/rclone/rclone.conf \
        sync /var/lib/n8n gcs:${bucketName}/n8n \
        --fast-list --transfers=4 --checkers=8 --delete-after

      echo "Backup completed"
    '';

    preStart = lib.mkIf (bucketName == "") ''
      echo "HERMES_GCS_BUCKET is not set. Set environment.variables.HERMES_GCS_BUCKET in configuration.nix"
    '';
  };

  systemd.timers.hermes-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "02:00";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/ntfy 0750 root root -"
    "d /var/lib/n8n 0750 root root -"
  ];
}
