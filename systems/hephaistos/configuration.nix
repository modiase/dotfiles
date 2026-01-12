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
    (heraklesBuildServer "hephaistos")
    ../../nix/homebrew.nix
  ];

  config = {
    nixpkgs.hostPlatform = "aarch64-darwin";
    programs.zsh.enable = true;
    system.stateVersion = 6;

    networking.hostName = "hephaistos";
    networking.computerName = "hephaistos";
    networking.localHostName = "hephaistos";

    users.users.moyeodiase = {
      name = "moyeodiase";
      home = "/Users/moyeodiase";
      openssh.authorizedKeys.keys = authorizedKeyLists.moye;
    };

    system.primaryUser = "moyeodiase";

    environment.etc.bashrc.enable = false;
    environment.etc.zshrc.enable = false;

    environment.systemPackages = with pkgs; [
      git
      vim
    ];
  };
}
