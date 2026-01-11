{
  config,
  pkgs,
  lib,
  modulesPath,
  authorizedKeyLists,
  ...
}:

let
  hardwareRepo = fetchTarball {
    url = "https://github.com/NixOS/nixos-hardware/archive/9c0ee5dfa186e10efe9b53505b65d22c81860fde.tar.gz";
    sha256 = "092yc6rp7xj4rygldv5i693xnhz7nqnrwrz1ky1kq9rxy2f5kl10";
  };
  dashboard = pkgs.callPackage ./run/dashboard { };
  encryptedKey = ''
    -----BEGIN PGP MESSAGE-----

    jA0ECQMKZfP5uVnNOd//0mIB7mc14m7zaN8zlZL5SYvaPbSvmKZypZwybLGFlyN6
    w6CgPLJ+F1WG/dRBCt922ujvCmRYS3jVvpn1Zoo5WG1/HiHU1l/sBGZOTSK1YBZm
    7/EWgKhLVFuBBuipvtY3ZtYI5Q==
    =GlBK
    -----END PGP MESSAGE-----
  '';
  firewallRules = [
    "FORWARD -i wg0 -o end0 -j ACCEPT"
    "FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT"
    "OUTPUT -d 192.168.0.0/16 -j ACCEPT"
    "OUTPUT -d 10.0.0.0/8 -j ACCEPT"
    "OUTPUT -d 172.16.0.0/12 -j ACCEPT"
    "OUTPUT -o lo -j ACCEPT"
    "OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT"
    "OUTPUT -p udp -d 162.159.200.1 --dport 123 -j ACCEPT"
    "OUTPUT -p udp -d 162.159.200.123 --dport 123 -j ACCEPT"
    "OUTPUT -p udp -d 216.239.35.0 --dport 123 -j ACCEPT"
    "OUTPUT -p udp -d 216.239.35.4 --dport 123 -j ACCEPT"
    "OUTPUT -p tcp -d 1.1.1.1 --dport 853 -j ACCEPT"
    "OUTPUT -p tcp -d 1.0.0.1 --dport 853 -j ACCEPT"
    "OUTPUT -p tcp -d 8.8.8.8 --dport 853 -j ACCEPT"
    "OUTPUT -p tcp -d 8.8.4.4 --dport 853 -j ACCEPT"
    "OUTPUT -j LOG --log-prefix \"FW_DROP: \" --log-level 4"
    "OUTPUT -j DROP"
  ];
in

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    "${hardwareRepo}/raspberry-pi/4"
    ./run/services/ssh-logger.nix
    ./run/services/wg-status-server.nix
    ./run/services/health-status-server.nix
    ./run/services/dns-logs-server.nix
    ./run/services/firewall-logs-server.nix
  ];

  config = {
    nixpkgs.hostPlatform = "aarch64-linux";

    boot.kernelPackages = pkgs.linuxPackages_latest;
    boot.supportedFilesystems = lib.mkForce [
      "vfat"
      "ext4"
    ];
    boot.initrd.availableKernelModules = [
      "xhci_pci"
      "usbhid"
      "usb_storage"
    ];

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;
    boot.kernelParams = [
      "8250.nr_uarts=1"
      "console=tty1"
      "cma=128M"
      "dyndbg=\"module wireguard +p\""
    ];

    boot.initrd.postMountCommands = ''
      mkdir -p $targetRoot/etc/wireguard
      echo '${encryptedKey}' | ${pkgs.gnupg}/bin/gpg --decrypt --quiet --batch --passphrase "$(cat /proc/device-tree/serial-number | tr -d '\0')" > $targetRoot/etc/wireguard/private.key
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
      util-linux
      gnupg
    ];

    hardware.enableRedistributableFirmware = true;

    nixpkgs.config.allowUnfree = true;

    networking.hostName = "hekate";
    networking.domain = "home";
    networking.extraHosts = "127.0.0.1 hekate";
    networking.useDHCP = true;
    networking.firewall.checkReversePath = "loose";
    networking.wireguard.interfaces.wg0 = {
      ips = [ "10.0.0.1/24" ];
      listenPort = 51820;
      mtu = 1280;
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
    networking.firewall = {
      enable = true;
      allowedUDPPorts = [
        51820
        5353
        53
      ];
      allowedTCPPorts = [
        22
        53
      ];
      extraCommands = lib.concatMapStringsSep "\n" (r: "iptables -A ${r}") firewallRules;
      extraStopCommands = lib.concatMapStringsSep "\n" (
        r: "iptables -D ${r} 2>/dev/null || true"
      ) firewallRules;
    };

    networking.nat = {
      enable = true;
      internalInterfaces = [ "wg0" ];
      externalInterface = "end0";
      forwardPorts = [ ];
      extraCommands = ''
        iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o end0 -j MASQUERADE
        iptables -t nat -A PREROUTING -d 10.0.100.0/24 -j NETMAP --to 192.168.1.0/24
      '';
      extraStopCommands = ''
        iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o end0 -j MASQUERADE 2>/dev/null || true
        iptables -t nat -D PREROUTING -d 10.0.100.0/24 -j NETMAP --to 192.168.1.0/24 2>/dev/null || true
      '';
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        LogLevel = "INFO";
      };
      extraConfig = ''
        Match User admin
          ForceCommand ${dashboard}/bin/hekate-dashboard
          AllowTcpForwarding no
          AllowAgentForwarding no
          X11Forwarding no
          PermitTunnel no
          AllowStreamLocalForwarding no
      '';
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

    services.unbound = {
      enable = true;
      enableRootTrustAnchor = false;
      settings = {
        server = {
          tls-cert-bundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
          interface = [
            "10.0.0.1"
            "192.168.1.110"
          ];
          access-control = [
            "192.168.1.0/24 allow"
            "10.0.0.0/24 allow"
          ];
          access-control-view = [
            "192.168.1.0/24 internal-view"
            "10.0.0.0/24 external-view"
          ];
          verbosity = 1;
          log-queries = "yes";
        };
        forward-zone = [
          {
            name = ".";
            forward-tls-upstream = "yes";
            forward-addr = [
              "1.1.1.1@853#cloudflare-dns.com"
              "1.0.0.1@853#cloudflare-dns.com"
              "8.8.8.8@853#dns.google"
              "8.8.4.4@853#dns.google"
            ];
          }
        ];
        view = [
          {
            name = "internal-view";
            view-first = "yes";
            local-zone = ''"home." static'';
            local-data = [
              ''"hestia.home. IN A 192.168.1.184"''
              ''"hekate.home. IN A 192.168.1.110"''
              ''"herakles.home. IN A 192.168.1.97"''
              ''"pallas.home. IN A 192.168.1.204"''
            ];
          }
          {
            name = "external-view";
            view-first = "yes";
            local-zone = ''"home." static'';
            local-data = [
              ''"hestia.home. IN A 10.0.100.184"''
              ''"hekate.home. IN A 10.0.100.110"''
              ''"herakles.home. IN A 10.0.100.97"''
              ''"pallas.home. IN A 10.0.100.204"''
            ];
          }
        ];
      };
    };

    systemd.services.avahi-daemon.serviceConfig = {
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateDevices = true;
      RestrictNamespaces = true;
      MemoryDenyWriteExecute = true;
      ProtectKernelTunables = true;
    };

    systemd.services.sshd.serviceConfig = {
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      RestrictNamespaces = true;
    };

    users.users.admin = {
      isNormalUser = true;
      home = "/home/admin";
      createHome = false;
      shell = "${pkgs.bash}/bin/bash";
      openssh.authorizedKeys.keys = authorizedKeyLists.moye;
    };

    security.sudo.enable = false;

    boot.kernel.sysctl = {
      "kernel.dmesg_restrict" = 1;
      "kernel.kptr_restrict" = 2;
      "net.core.bpf_jit_harden" = 2;
      "kernel.unprivileged_userns_clone" = 0;
    };

    users.users.root.hashedPassword = "!";

    nix.settings.allowed-users = [ "root" ];

    services.timesyncd = {
      enable = true;
      servers = [
        "162.159.200.1"
        "162.159.200.123"
        "216.239.35.0"
        "216.239.35.4"
      ];
    };

    systemd.tmpfiles.rules = [
      "d /var/log 0755 root root - -"
      "d /home/admin 0555 root root - -"
      "Z /tmp 0700 root root - -"
      "Z /var/tmp 0700 root root - -"
    ];

    system.stateVersion = "24.11";
  };
}
