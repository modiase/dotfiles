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

let
  hardwareRepo = fetchTarball {
    url = "https://github.com/NixOS/nixos-hardware/archive/9c0ee5dfa186e10efe9b53505b65d22c81860fde.tar.gz";
    sha256 = "092yc6rp7xj4rygldv5i693xnhz7nqnrwrz1ky1kq9rxy2f5kl10";
  };
in

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    "${hardwareRepo}/raspberry-pi/4"
    commonNixSettings
    (heraklesBuildServer "hestia")
    ./services/nginx.nix
    ./services/tk700-dashboard.nix
  ];

  config = {
    nixpkgs.hostPlatform = "aarch64-linux";
    nixpkgs.config.allowUnfree = true;

    boot.kernelPackages = pkgs.linuxPackages;
    boot.initrd.availableKernelModules = [
      "usb_storage"
      "usbhid"
      "xhci_pci"
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
        1883
        2022
        8080
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

    services.eternal-terminal.enable = true;

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        domain = true;
      };
    };

    services.mosquitto = {
      enable = true;
      listeners = [
        {
          address = "127.0.0.1";
          port = 1883;
        }
      ];
    };

    services.zigbee2mqtt = {
      enable = true;
      settings = {
        homeassistant = {
          enabled = true;
        };
        permit_join = false;
        mqtt = {
          server = "mqtt://127.0.0.1:1883";
        };
        serial = {
          port = "/dev/zigbee";
          adapter = "zstack";
        };
        frontend = {
          port = 8080;
        };
      };
    };

    services.udev.extraRules = ''
      SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", MODE="0666", GROUP="dialout"
      SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", SYMLINK+="zigbee", MODE="0666", GROUP="dialout"
    '';

    users.users.zigbee2mqtt.extraGroups = [ "dialout" ];

    services.home-assistant = {
      enable = true;
      extraComponents = [
        "apple_tv"
        "homekit_controller"
        "hue"
        "ipp"
        "isal"
        "mqtt"
        "ntfy"
        "open_meteo"
        "sonos"
        "tado"
        "thread"
        "todoist"
        "zha"
      ];
      extraPackages =
        python3Packages: with python3Packages; [
          zlib-ng
        ];
      customComponents = with pkgs.home-assistant-custom-components; [
        adaptive_lighting
        localtuya
        octopus_energy
      ];
      customLovelaceModules = with pkgs.home-assistant-custom-lovelace-modules; [
        card-mod
      ];
      config = {
        default_config = { };
        automation = "!include automations.yaml";
        adaptive_lighting = { };
        homeassistant = {
          elevation = "!secret elevation";
          latitude = "!secret latitude";
          longitude = "!secret longitude";
          name = "Hestia";
          time_zone = "Europe/London";
          unit_system = "metric";
          external_url = "http://hestia.local/hass";
          internal_url = "http://127.0.0.1:8123";
        };
        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = [
            "127.0.0.1"
            "::1"
          ];
        };
        logger = {
          default = "info";
        };
        frontend = {
          themes = "!include_dir_merge_named themes";
        };
      };
    };

    systemd.services.home-assistant.serviceConfig = {
      AmbientCapabilities = lib.mkForce [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
      CapabilityBoundingSet = lib.mkForce [
        "CAP_NET_ADMIN"
        "CAP_NET_RAW"
      ];
    };

    system.activationScripts.homeAssistantThemes = lib.stringAfter [ "var" ] ''
      install -d -o hass -g hass -m 0755 /var/lib/hass/themes
      ${pkgs.curl}/bin/curl -sL -o /var/lib/hass/themes/frosted-glass.yaml \
        "https://raw.githubusercontent.com/wessamlauf/homeassistant-frosted-glass-themes/main/themes/Frosted%20Glass.yaml"
      ${pkgs.curl}/bin/curl -sL -o /var/lib/hass/themes/frosted-glass-dark.yaml \
        "https://raw.githubusercontent.com/wessamlauf/homeassistant-frosted-glass-themes/main/themes/Frosted%20Glass%20Dark.yaml"
      ${pkgs.curl}/bin/curl -sL -o /var/lib/hass/themes/frosted-glass-light.yaml \
        "https://raw.githubusercontent.com/wessamlauf/homeassistant-frosted-glass-themes/main/themes/Frosted%20Glass%20Light.yaml"
      chown hass:hass /var/lib/hass/themes/*.yaml
    '';

    users.users.moye = {
      isNormalUser = true;
      home = "/home/moye";
      shell = pkgs.bash;
      extraGroups = [
        "sudo"
        "wheel"
      ];
      openssh.authorizedKeys.keys = authorizedKeyLists.moye;
    };

    users.users.root.hashedPassword = "!";

    security.sudo = {
      enable = true;
      wheelNeedsPassword = false;
    };

    nix.settings = {
      max-jobs = 0;
      cores = 0;
    };

    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedPriority = 7;

    environment.systemPackages = with pkgs; [
      curl
      git
      gnupg
      google-cloud-sdk
      pinentry-curses
      rsync
      util-linux
    ];

    systemd.services.systemd-networkd-wait-online.enable = false;

    system.stateVersion = "24.11";
  };
}
