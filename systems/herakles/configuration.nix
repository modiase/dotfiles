{
  config,
  lib,
  pkgs,
  authorizedKeyLists,
  commonNixSettings,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    commonNixSettings
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  networking.hostName = "herakles";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/London";

  i18n.defaultLocale = "en_GB.UTF-8";

  users.users.moye = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    createHome = true;
    openssh.authorizedKeys.keys = authorizedKeyLists.moye;
  };

  security.sudo.extraRules = [
    {
      users = [ "moye" ];
      commands = [
        {
          command = "ALL";
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    git
    jq
    nix-prefetch
    nvitop
    vim
    wget
  ];

  services.openssh = {
    enable = true;
    settings = {
      X11Forwarding = true;
    };
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  networking.firewall.enable = false;

  nixpkgs.config.allowUnfree = true;

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    package = config.hardware.nvidia.package;
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    nvidiaSettings = true;
  };

  nixpkgs.config.cudaSupport = true;

  hardware.nvidia-container-toolkit.enable = true;

  nix.settings = {
    max-jobs = 16;
    substituters = [
      "https://cache.nixos.org"
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkgKbtJrytuOoQqR5RQY="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
  };

  system.stateVersion = "25.05";
  virtualisation.docker.enable = true;

  services.slurm = (import ../shared/slurm-cluster.nix { }) // {
    server.enable = true;
    client.enable = true;
    controlMachine = "herakles";
  };

  services.munge = {
    enable = true;
    password = "/var/secrets/munge.key";
  };

  system.activationScripts.setupMungeKey = ''
    mkdir -p /var/secrets
    if [ -f /home/moye/Dotfiles/secrets/munge.key ]; then
      cp /home/moye/Dotfiles/secrets/munge.key /var/secrets/munge.key
      chown munge:munge /var/secrets/munge.key
      chmod 0400 /var/secrets/munge.key
    fi
  '';

  environment.etc."slurm/gres.conf".text = ''
    NodeName=herakles Name=gpu File=/dev/nvidia0
  '';

  system.activationScripts.setupSlurmDirs = ''
    mkdir -p /var/log/slurm
    chown slurm:slurm /var/log/slurm
  '';
}
