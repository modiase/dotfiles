{ config, pkgs, ... }:

let
  ports = import ../ports.nix;
in
{
  services.mongodb = {
    enable = true;
    enableAuth = true;
    bind_ip = "127.0.0.1";
    initialRootPasswordFile = pkgs.writeText "mongodb-password" "mongodb";
    extraConfig = ''
      storage:
        wiredTiger:
          engineConfig:
            cacheSizeGB: 1
      net:
        port: ${toString ports.mongodb}
    '';
  };

  systemd.services.mongodb.serviceConfig = {
    LimitNOFILE = 64000;
    LimitNPROC = 64000;
  };
  systemd.services.mongodb-backup = {
    description = "MongoDB backup service";
    after = [ "mongodb.service" ];
    wants = [ "mongodb.service" ];

    serviceConfig = {
      Type = "oneshot";
      User = "mongodb-backup";
      Group = "mongodb-backup";
      ExecStart = pkgs.writeShellScript "mongodb-backup" ''
        set -euo pipefail

        BACKUP_DIR="/var/lib/mongodb-backups"
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

        mkdir -p "$BACKUP_PATH"
        ${pkgs.mongodb-tools}/bin/mongodump --username root --password mongodb --authenticationDatabase admin --out "$BACKUP_PATH"
        cd "$BACKUP_DIR"
        tar -czf "$TIMESTAMP.tar.gz" "$TIMESTAMP"
        rm -rf "$TIMESTAMP"
        find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
        echo "Backup completed: $TIMESTAMP.tar.gz"
      '';
    };
  };

  systemd.timers.mongodb-backup = {
    description = "MongoDB backup timer - every 10 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*:0/10";
      Persistent = true;
      AccuracySec = "1min";
    };
  };

  users.users.mongodb-backup = {
    isSystemUser = true;
    group = "mongodb-backup";
    description = "MongoDB backup service user";
  };

  users.groups.mongodb-backup = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/mongodb-backups 0755 mongodb-backup mongodb-backup -"
  ];
}
