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
    (pkgs.callPackage ../nixpkgs/apple-containers.nix { })
  ];
}
