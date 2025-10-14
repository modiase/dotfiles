{
  config,
  pkgs,
  lib,
  modulesPath,
  authorizedKeyLists,
  commonNixSettings,
  heraklesBuildServer,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    "${
      fetchTarball {
        url = "https://github.com/NixOS/nixos-hardware/tarball/master";
        sha256 = "19cld3jnzxjw92b91hra3qxx41yhxwl635478rqp0k4nl9ak2snq";
      }
    }/raspberry-pi/4"
    commonNixSettings
    (heraklesBuildServer "hestia")
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nixpkgs.config.allowUnfree = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
  ];

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelParams = [
    "8250.nr_uarts=1"
    "console=ttyAMA0,115200"
    "console=tty1"
    "cma=128M"
  ];

  hardware.enableRedistributableFirmware = true;

  networking.hostName = "hestia";
  networking.domain = "home";
  networking.extraHosts = "127.0.0.1 hestia";
  networking.useDHCP = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      80
    ];
    allowedUDPPorts = [
      5353
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      LogLevel = "INFO";
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
    };
  };

  services.home-assistant = {
    enable = true;
    config = {
      default_config = { };
      homeassistant = {
        elevation = "!secret elevation";
        latitude = "!secret latitude";
        longitude = "!secret longitude";
        name = "Hestia";
        time_zone = "Europe/London";
        unit_system = "metric";
      };
      http = {
        server_host = "0.0.0.0";
        server_port = 80;
      };
      logger = {
        default = "info";
      };
    };
  };

  users.users.moye = {
    isNormalUser = true;
    home = "/home/moye";
    shell = pkgs.bash;
    extraGroups = [
      "wheel"
      "sudo"
    ];
    openssh.authorizedKeys.keys = authorizedKeyLists.moye;
  };

  users.users.root.hashedPassword = "!";

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    google-cloud-sdk
    rsync
    util-linux
  ];

  systemd.services.systemd-networkd-wait-online.enable = false;

  environment.etc."backup-hass.sh" = {
    text = ''
      #!/bin/bash
      set -euo pipefail

      if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        echo "Error: No active gcloud authentication found. Run 'gcloud auth login'" >&2
        exit 1
      fi

      backup_dir="/tmp/hass-backup-$(date +%Y%m%d-%H%M%S)"
      backup_file="hestia-hass-$(date +%Y%m%d-%H%M%S).tar.gz"

      rsync -av /var/lib/hass/ "$backup_dir/"
      tar -czf "/tmp/$backup_file" -C "$backup_dir" .
      gsutil cp "/tmp/$backup_file" "gs://modiase-backups/hestia/"

      rm -rf "$backup_dir" "/tmp/$backup_file"
      echo "Backup completed: gs://modiase-backups/hestia/$backup_file"
    '';
    mode = "0755";
  };

  environment.etc."restore-hass.sh" = {
    text = ''
      #!/bin/bash
      set -euo pipefail

      if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
        echo "Error: No active gcloud authentication found. Run 'gcloud auth login'" >&2
        exit 1
      fi

      backup_file="''${1:-$(gsutil ls gs://modiase-backups/hestia/ | sort | tail -1 | sed 's|.*/||')}"
      restore_dir="/tmp/hass-restore-$(date +%Y%m%d-%H%M%S)"

      echo "Restoring from: $backup_file"
      gsutil cp "gs://modiase-backups/hestia/$backup_file" "/tmp/$backup_file"
      mkdir -p "$restore_dir"
      tar -xzf "/tmp/$backup_file" -C "$restore_dir"

      systemctl stop home-assistant
      rsync -av --delete "$restore_dir/" /var/lib/hass/
      systemctl start home-assistant

      rm -rf "$restore_dir" "/tmp/$backup_file"
      echo "Restore completed from: $backup_file"
    '';
    mode = "0755";
  };

  systemd.services.home-assistant-backup = {
    description = "Home Assistant Configuration Backup";
    serviceConfig = {
      ExecStart = "/etc/backup-hass.sh";
      Type = "oneshot";
      User = "root";
    };
  };

  systemd.timers.home-assistant-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };

  systemd.services.home-assistant-restore = {
    description = "Home Assistant Configuration Restore";
    serviceConfig = {
      ExecStart = "/etc/restore-hass.sh";
      Type = "oneshot";
      User = "root";
    };
  };

  system.stateVersion = "24.11";
}
