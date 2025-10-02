{ config, pkgs, ... }:

{
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
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      hostName = "herakles";
      system = "x86_64-linux";
      sshUser = "moye";
      sshKey = "/var/root/.ssh/herakles_ed25519";
      maxJobs = 8;
      speedFactor = 1;
    }
  ];
  programs.zsh.enable = true;
  system.stateVersion = 6;

  networking.hostName = "pallas";
  networking.computerName = "pallas";
  networking.localHostName = "pallas";

  users.users.moye = {
    name = "moye";
    home = "/Users/moye";
  };

  system.primaryUser = "moye";

  environment.systemPackages = with pkgs; [
    vim
    git
    yabai
    skhd
  ];

  fonts.packages = with pkgs; [
    nerd-fonts.iosevka
    space-grotesk
    lato
  ];

  launchd.user.agents.yabai = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.yabai}/bin/yabai" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/yabai.out.log";
      StandardErrorPath = "/tmp/yabai.err.log";
    };
  };

  launchd.user.agents.skhd = {
    serviceConfig = {
      ProgramArguments = [ "${pkgs.skhd}/bin/skhd" ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/tmp/skhd.out.log";
      StandardErrorPath = "/tmp/skhd.err.log";
    };
  };

}
