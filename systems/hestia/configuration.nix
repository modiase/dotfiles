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

  boot.kernelPackages = pkgs.linuxPackages;
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
    extraComponents = [
      "apple_tv"
      "hue"
      "tado"
      "todoist"
    ];
    customComponents = [ ];
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

  systemd.services.home-assistant.serviceConfig = {
    AmbientCapabilities = lib.mkForce [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
    ];
    CapabilityBoundingSet = lib.mkForce [
      "CAP_NET_ADMIN"
      "CAP_NET_RAW"
      "CAP_NET_BIND_SERVICE"
    ];
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

  system.stateVersion = "24.11";
}
