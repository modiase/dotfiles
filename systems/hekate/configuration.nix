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
  encryptedKey = ''
    -----BEGIN PGP MESSAGE-----

    jA0ECQMKZfP5uVnNOd//0mIB7mc14m7zaN8zlZL5SYvaPbSvmKZypZwybLGFlyN6
    w6CgPLJ+F1WG/dRBCt922ujvCmRYS3jVvpn1Zoo5WG1/HiHU1l/sBGZOTSK1YBZm
    7/EWgKhLVFuBBuipvtY3ZtYI5Q==
    =GlBK
    -----END PGP MESSAGE-----
  '';
in

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
    "${hardwareRepo}/raspberry-pi/4"
  ];

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
    "console=ttyAMA0,115200"
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

  environment.etc."rbash-wrapper".source = pkgs.writeShellScript "rbash-wrapper" ''
    #!/bin/bash
    export PATH="/var/lib/rbash-bin"
    export PS1='\[\033[1;37m\]hekate\[\033[0m\]> '
    cd /var/log 2>/dev/null || cd /
    exec ${pkgs.bash}/bin/bash --restricted --norc --noprofile
  '';

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
      53
      5353
    ];
    allowedTCPPorts = [
      53
      22
    ];
    extraCommands = ''
      iptables -A FORWARD -i wg0 -o end0 -j ACCEPT
      iptables -A FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT

      iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT
      iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
      iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
      iptables -A OUTPUT -o lo -j ACCEPT
      iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
      iptables -A OUTPUT -j DROP
    '';
    extraStopCommands = ''
      iptables -D FORWARD -i wg0 -o end0 -j ACCEPT 2>/dev/null || true
      iptables -D FORWARD -i end0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

      iptables -D OUTPUT -d 192.168.0.0/16 -j ACCEPT 2>/dev/null || true
      iptables -D OUTPUT -d 10.0.0.0/8 -j ACCEPT 2>/dev/null || true
      iptables -D OUTPUT -d 172.16.0.0/12 -j ACCEPT 2>/dev/null || true
      iptables -D OUTPUT -o lo -j ACCEPT 2>/dev/null || true
      iptables -D OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      iptables -D OUTPUT -j DROP 2>/dev/null || true
    '';
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
        ForceCommand /etc/rbash-wrapper
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

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "net.core.bpf_jit_harden" = 2;
    "kernel.unprivileged_userns_clone" = 0;
  };

  users.users.root.hashedPassword = "!";

  nix.settings.allowed-users = [ "root" ];

  security.sudo.enable = false;

  systemd.services.ssh-logger = {
    description = "SSH connection logger";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c 'journalctl -f -u sshd | tee -a /var/log/ssh-access.log'";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  services.logrotate = {
    enable = true;
    settings = {
      "/var/log/ssh-access.log" = {
        frequency = "daily";
        rotate = 7;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        postrotate = "systemctl reload rsyslog";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log 0755 root root - -"
    "f /var/log/ssh-access.log 0644 root root - -"
    "d /home/admin 0555 root root - -"
    "d /var/lib/rbash-bin 0755 root root - -"
    "L+ /var/lib/rbash-bin/cat - - - - ${pkgs.coreutils}/bin/cat"
    "L+ /var/lib/rbash-bin/ls - - - - ${pkgs.coreutils}/bin/ls"
    "L+ /var/lib/rbash-bin/head - - - - ${pkgs.coreutils}/bin/head"
    "L+ /var/lib/rbash-bin/tail - - - - ${pkgs.coreutils}/bin/tail"
    "L+ /var/lib/rbash-bin/grep - - - - ${pkgs.gnugrep}/bin/grep"
    "L+ /var/lib/rbash-bin/pwd - - - - ${pkgs.coreutils}/bin/pwd"
    "L+ /var/lib/rbash-bin/whoami - - - - ${pkgs.coreutils}/bin/whoami"
    "L+ /var/lib/rbash-bin/echo - - - - ${pkgs.coreutils}/bin/echo"
    "L+ /var/lib/rbash-bin/clear - - - - ${pkgs.ncurses}/bin/clear"
    "Z /tmp 0700 root root - -"
    "Z /var/tmp 0700 root root - -"
  ];

  system.stateVersion = "24.11";
}
