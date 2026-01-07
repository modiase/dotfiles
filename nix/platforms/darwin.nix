{ pkgs, ... }:

let
  secrets = pkgs.callPackage ../nixpkgs/secrets { };
  ntfy-me = pkgs.callPackage ../nixpkgs/ntfy-me { inherit secrets; };
in
{
  imports = [
    ../skhd.nix
    ../yabai.nix
  ];

  nixpkgs.config.allowUnfree = true;

  home.packages = with pkgs; [
    colima
    coreutils-prefixed
    iproute2mac
    gettext
    gnupg
    (pkgs.callPackage ../nixpkgs/apple-containers.nix { })
    zstd
  ];

  home.file.".local/bin/bash" = {
    source = "${pkgs.bash}/bin/bash";
  };

  launchd.agents.ntfy-listen = {
    enable = true;
    config = {
      ProgramArguments = [ "${ntfy-me}/bin/ntfy-listen" ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/ntfy-listen.log";
      StandardErrorPath = "/tmp/ntfy-listen.err";
    };
  };
}
