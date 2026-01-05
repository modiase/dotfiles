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
  imports = [
    commonNixSettings
    darwinFrontendServices
    (heraklesBuildServer "pallas")
    ../../nix/homebrew.nix
  ];

  config = {
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

    environment.etc."resolver/home".text = "nameserver 192.168.1.1\n";

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
