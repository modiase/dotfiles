{
  config,
  pkgs,
  modulesPath,
  ...
}:

let
  authorizedKeys = import ../authorized-keys.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ./services/ntfy.nix
    ./services/n8n.nix
    ./services/nginx.nix
    ./services/backups.nix
    (modulesPath + "/virtualisation/google-compute-image.nix")
  ];

  networking.hostName = "hermes";
  time.timeZone = "Europe/London";

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "n8n"
    ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    rsync
    curl
    rclone
  ];

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users.moye = {
    isNormalUser = true;
    createHome = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = builtins.attrValues authorizedKeys.moye;
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
    extraRules = [
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
  };

  systemd.services.clone-dotfiles = {
    description = "Clone Dotfiles repo for moye";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "moye";
      WorkingDirectory = "/home/moye";
    };
    script = ''
      if [ ! -d Dotfiles ]; then
        git clone --depth 1 https://github.com/moye/Dotfiles Dotfiles
      fi
    '';
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22
      80
      443
    ];
  };

  environment.variables.HERMES_GCS_BUCKET = "modiase-infra-hermes";

  system.stateVersion = "24.05";
}
