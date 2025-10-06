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

  environment.etc."n8n/hooks.js" = {
    source = ./n8n-hooks.js;
    mode = "0644";
  };

  environment.etc."n8n/setup.py" = {
    source = ./n8n-setup.py;
    mode = "0755";
  };

  services.n8n = {
    enable = true;
    webhookUrl = "https://n8n.${rootDomain}/webhook/";
    settings = {
      port = ports.n8n;
      editorBaseUrl = "https://n8n.${rootDomain}/";
      nodes_include = "['n8n-nodes-*']";
      external_hook_files = "/etc/n8n/hooks.js";
    };
  };

  systemd.services.n8n = {
    serviceConfig = {
      ReadOnlyPaths = [ "/etc/n8n" ];
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
