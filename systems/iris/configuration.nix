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
    ../../nix/homebrew.nix
  ];

  config = {
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

    environment.etc."resolver/home".text = "nameserver 10.0.0.1\n";

    environment.systemPackages = with pkgs; [
      git
      vim
    ];

    programs.ssh.extraConfig = ''
      Include /Users/moye/.colima/ssh_config

      Host *
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

      Match host hestia exec "ping -c1 -W3 10.0.100.184 >/dev/null 2>&1"
          HostName 10.0.100.184
          ServerAliveInterval 60

      Host hestia
          HostName 192.168.1.184
          HostKeyAlias hestia

      Host hermes
          HostName 34.39.105.36
    '';
  };
}
