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
  ];

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
    vim
    git
  ];

  environment.etc."slurm/slurm.conf".text = import ../shared/slurm-client-config.nix {
    controlAddr = "herakles.local";
  };

}
