{
  config,
  lib,
  pkgs,
  authorizedKeyLists,
  commonNixSettings,
  llm-server,
  ...
}:

{
  options.dotfiles.manageRemotely = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Whether this host can be managed remotely via activate --host";
  };

  imports = [
    ./hardware-configuration.nix
    commonNixSettings
    llm-server.nixosModules.default
  ];

  config = {
    dotfiles.manageRemotely = true;

    # Enable the LLM Server service
    services.llm-server = {
      enable = true;
      gpuMemoryUtilization = 0.90;
      maxModelLen = 24576;
      maxNumSeqs = 64;
    };

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
      (pkgs.symlinkJoin {
        name = "nvitop-wrapped";
        paths = [ nvitop ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/nvitop \
            --prefix LD_LIBRARY_PATH : "${config.hardware.nvidia.package}/lib"
        '';
      })
      vim
      wget
    ];

    services.openssh.enable = true;
    services.eternal-terminal.enable = true;

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
      trusted-users = [ "moye" ];
      secret-key-files = [ "/etc/nix/signing-key.sec" ];
      post-build-hook = pkgs.writeShellScript "post-build-hook" ''
        set -eu
        set -f
        export IFS=' '

        for path in $OUT_PATHS; do
          ${pkgs.nix}/bin/nix store sign --key-file /etc/nix/signing-key.sec "$path"
        done
      '';
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
  };
}
