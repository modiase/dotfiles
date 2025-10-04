{
  config,
  pkgs,
  authorizedKeyLists,
  darwinFrontendServices,
  heraklesBuildServer,
  ...
}:

{
  imports = [
    darwinFrontendServices
    (heraklesBuildServer "pallas")
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "moye"
    ];
  };
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

  environment.systemPackages = with pkgs; [
    vim
    git
  ];

}
