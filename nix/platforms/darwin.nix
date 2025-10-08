{ pkgs, ... }:

{
  imports = [
    ../skhd.nix
    ../yabai.nix
  ];

  home.packages = with pkgs; [
    colima
    coreutils-prefixed
    iproute2mac
    gettext
    gnupg
    (pkgs.callPackage ../nixpkgs/apple-containers.nix { })
    xquartz
    xorg.xauth
    zstd
  ];

  home.file.".local/bin/bash" = {
    source = "${pkgs.bash}/bin/bash";
  };
}
