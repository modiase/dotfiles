{
  config,
  pkgs,
  authorizedKeyLists,
  commonNixSettings,
  darwinFrontendServices,
  heraklesBuildServer,
  ...
}:

{
  options.dotfiles.manageRemotely = pkgs.lib.mkOption {
    type = pkgs.lib.types.bool;
    default = false;
    description = "Whether this host can be managed remotely via activate --host";
  };

  imports = [
    commonNixSettings
    darwinFrontendServices
    (heraklesBuildServer "pallas")
    ../../nix/homebrew.nix
  ];

  config = {
    dotfiles.manageRemotely = true;

    nixpkgs.hostPlatform = "aarch64-darwin";
    programs.zsh.enable = true;
    system.stateVersion = 6;

    networking.hostName = "pallas";
    networking.computerName = "pallas";
    networking.localHostName = "pallas";

    users.users.moye = {
      name = "moye";
      home = "/Users/moye";
      openssh.authorizedKeys.keys = authorizedKeyLists.moye;
    };

    system.primaryUser = "moye";

    security.sudo.extraConfig = ''
      moye ALL=(ALL) NOPASSWD: ALL
    '';

    environment.systemPackages = with pkgs; [
      eternal-terminal
      git
      vim
    ];

    launchd.daemons.etserver = {
      serviceConfig = {
        ProgramArguments = [ "${pkgs.eternal-terminal}/bin/etserver" ];
        KeepAlive = true;
        RunAtLoad = true;
        StandardOutPath = "/tmp/etserver.out.log";
        StandardErrorPath = "/tmp/etserver.err.log";
      };
    };
  };
}
