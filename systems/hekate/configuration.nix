{
  config,
  pkgs,
  lib,
  modulesPath,
  authorizedKeyLists,
  ...
}:

let
  wireguardKey = builtins.getEnv "HEKATE_WG_KEY";
in

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  fileSystems."/" = lib.mkForce {
    device = "none";
    fsType = "tmpfs";
    options = [
      "size=256M"
      "mode=755"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [
      "ro"
      "noatime"
    ];
  };

  nix.enable = false;
  systemd.services.nix-daemon.enable = false;

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelParams = [
    "console=tty0" # HDMI output
    "console=ttyAMA0,115200" # Serial as backup
  ];

  # !!! KEY SECURITY: Embed WireGuard key in initrd, NOT the Nix store !!!
  boot.initrd.secrets = lib.mkIf (wireguardKey != "") {
    "/etc/wireguard/private.key" = pkgs.writeText "wg-key" wireguardKey;
  };

  boot.initrd.postMountCommands = lib.mkIf (wireguardKey != "") ''
    mkdir -p $targetRoot/etc/wireguard
    cp /etc/wireguard/private.key $targetRoot/etc/wireguard/private.key
    chmod 400 $targetRoot/etc/wireguard/private.key
    chown root:root $targetRoot/etc/wireguard/private.key
  '';

  documentation.enable = false;
  documentation.nixos.enable = false;
  documentation.man.enable = false;
  documentation.info.enable = false;
  documentation.doc.enable = false;

  services.thermald.enable = false;
  programs.command-not-found.enable = false;
  programs.nano.enable = false;

  environment.defaultPackages = [ ];
  environment.systemPackages = with pkgs; [
    vim
    htop
    util-linux
  ];

  networking.hostName = "hekate";
  networking.domain = "home";
  networking.extraHosts = "127.0.0.1 hekate.home hekate";
  networking.useDHCP = true;
  networking.firewall.checkReversePath = "loose";
  networking.wireguard.interfaces.wg0 = lib.mkIf (wireguardKey != "") {
    ips = [ "10.0.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = "/etc/wireguard/private.key";
    peers = [
      {
        # iris
        publicKey = "Od72AK2AKZptCZcGJ+PvF78/9EwlFonpWP8X/fCzLGE=";
        allowedIPs = [ "10.0.0.2/32" ];
        persistentKeepalive = 21;
      }
      {
        # pegasus
        publicKey = "/tdJioXk+bkkn0HIATk9t5nMNZMTVqHc3KJA5+vm+w8=";
        allowedIPs = [ "10.0.0.3/32" ];
        persistentKeepalive = 21;
      }
    ];
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      server = [
        "1.1.1.1"
        "8.8.8.8"
      ];
      local = "/home/";
      domain = "home";
      address = [
        "/router.home/10.0.100.1"
        "/herakles.home/10.0.100.97"
        "/hekate.home/10.0.100.110"
        "/pallas.home/10.0.100.204"
      ];
      interface = [
        "wg0"
        "eth0"
      ];
      listen-address = [
        "10.0.0.1"
      ];
    };
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [
      51820
      53
      5353
    ];
    allowedTCPPorts = [
      53
      22
    ];
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  systemd.services."getty@tty1" = {
    enable = true;
    wantedBy = [ "multi-user.target" ];
  };

  systemd.services.systemd-networkd-wait-online.enable = false;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      domain = true;
    };
  };

  users.users.moye = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = authorizedKeyLists.moye;
  };

  users.users.root.hashedPassword = "!";

  system.stateVersion = "24.11";
}
