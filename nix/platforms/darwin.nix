{ pkgs, ... }:

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
}
