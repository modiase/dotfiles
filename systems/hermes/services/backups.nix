{
  config,
  pkgs,
  lib,
  ...
}:

let
  bucketName =
    let
      bucket = builtins.getEnv "HERMES_GCS_BUCKET";
    in
    if bucket != "" then bucket else (config.environment.variables.HERMES_GCS_BUCKET or "");
  rcloneConf = ''
    [gcs]
    type = gcs
    env_auth = true
    bucket_policy_only = true
  '';

  commonServiceConfig = {
    Type = "oneshot";
    User = "root";
  };

  commonPath = [
    pkgs.rclone
    pkgs.coreutils
    pkgs.bash
    pkgs.rsync
  ];

  rcloneFlags = "--config /etc/rclone/rclone.conf --fast-list --transfers=4 --checkers=8 --gcs-no-check-bucket";
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

    serviceConfig = commonServiceConfig;
    path = commonPath;

    script = ''
      set -euo pipefail

      if ${pkgs.rclone}/bin/rclone ${rcloneFlags} ls gcs:${bucketName}/ntfy-sh >/dev/null 2>&1; then
        ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync gcs:${bucketName}/ntfy-sh /var/lib/ntfy-sh
      fi

      if ${pkgs.rclone}/bin/rclone ${rcloneFlags} ls gcs:${bucketName}/n8n >/dev/null 2>&1; then
        ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync gcs:${bucketName}/n8n /var/lib/n8n
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

    serviceConfig = commonServiceConfig;
    path = commonPath;

    script = lib.mkIf (bucketName != "") ''
      set -euo pipefail

      echo "Backing up ntfy-sh to gcs:${bucketName}/ntfy-sh ..."
      ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync /var/lib/ntfy-sh gcs:${bucketName}/ntfy-sh --delete-after

      echo "Backing up n8n to gcs:${bucketName}/n8n ..."
      ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync /var/lib/n8n gcs:${bucketName}/n8n --delete-after

      echo "Backup completed"
    '';

    preStart = lib.mkIf (bucketName == "") ''
      echo "HERMES_GCS_BUCKET is not set. Set environment.variables.HERMES_GCS_BUCKET in configuration.nix"
    '';
  };

  systemd.timers.hermes-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
  };

}
