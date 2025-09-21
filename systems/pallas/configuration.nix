{ config, pkgs, ... }:

{
  nixpkgs.hostPlatform = "aarch64-darwin";
  nix.settings.experimental-features = "nix-command flakes";
  programs.zsh.enable = true;
  system.stateVersion = 6;

  networking.hostName = "pallas";
  networking.ComputerName = "pallas";
  networking.localHostName = "pallas";

  users.users.moye = {
    name = "moye";
    home = "/Users/moye";
  };

  environment.systemPackages = with pkgs; [
    vim
    git
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    space-grotesk
    lato
  ];
}
