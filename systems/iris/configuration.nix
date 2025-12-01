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

  programs.ssh.extraConfig = ''
    Include /Users/moye/.colima/ssh_config

    Host *
        SetEnv TERM=alacritty
        IdentityFile ~/.ssh/iris.pem

    Match host pallas exec "ping -c1 -W3 10.0.100.204 >/dev/null 2>&1"
        HostName 10.0.100.204
        ServerAliveInterval 60

    Host pallas
        HostName 192.168.1.204

    Match host hekate exec "ping -c1 -W3 10.0.100.110 >/dev/null 2>&1"
        HostName 10.0.100.110
        ServerAliveInterval 60

    Host hekate
        User admin
        HostName 192.168.1.110
        HostKeyAlias hekate

    Match host herakles exec "ping -c1 -W3 10.0.100.97 >/dev/null 2>&1"
        HostName 10.0.100.97
        ServerAliveInterval 60

    Host herakles
        HostName 192.168.1.97
        HostKeyAlias herakles

    Host hermes
        HostName 34.39.105.36

    Host hestia
        HostName hestia.local
  '';

}
