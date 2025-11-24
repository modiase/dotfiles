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
    (heraklesBuildServer "iris")
  ];

  nixpkgs.hostPlatform = "aarch64-darwin";
  programs.zsh.enable = true;
  system.stateVersion = 6;

  networking.hostName = "iris";
  networking.computerName = "iris";
  networking.localHostName = "iris";

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
