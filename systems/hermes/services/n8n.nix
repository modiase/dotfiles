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

  services.n8n = {
    enable = true;
    environment = {
      WEBHOOK_URL = "https://n8n.${rootDomain}/webhook/";
      N8N_PORT = toString ports.n8n;
      N8N_EDITOR_BASE_URL = "https://n8n.${rootDomain}/";
      NODES_INCLUDE = "['n8n-nodes-*']";
      N8N_USER_MANAGEMENT_DISABLED = "true";
    };
  };

  systemd.services.n8n = {
    environment.GENERIC_TIMEZONE = "Europe/London";
    serviceConfig = {
      TimeoutStartSec = "10min";
    };
    preStart = ''
      if [ -f /var/lib/n8n/.n8n/config ]; then
        chmod 600 /var/lib/n8n/.n8n/config
      fi
    '';
  };

  systemd.services.n8n-restore = lib.mkIf (bucketName != "") {
    description = "Restore n8n data from GCS";
    wantedBy = [ "multi-user.target" ];
    before = [ "n8n.service" ];
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
      if ${pkgs.rclone}/bin/rclone ${rcloneFlags} ls gcs:${bucketName}/n8n >/dev/null 2>&1; then
        ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync gcs:${bucketName}/n8n /var/lib/n8n
      fi
    '';
  };

  systemd.services.n8n-backup = lib.mkIf (bucketName != "") {
    description = "Backup n8n data to GCS";
    after = [
      "network-online.target"
      "n8n-restore.service"
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
      echo "Backing up n8n to gcs:${bucketName}/n8n ..."
      ${pkgs.rclone}/bin/rclone ${rcloneFlags} sync /var/lib/n8n gcs:${bucketName}/n8n --delete-after
      echo "Backup completed"
    '';
  };

  systemd.timers.n8n-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/5";
      Persistent = true;
      RandomizedDelaySec = "30s";
    };
  };
}
