{ config, pkgs, system, lib, ... }:

{
  imports = [
    ./alacritty.nix
    ./bash.nix
    ./bat.nix
    ./btop.nix
    ./fish.nix
    ./git.nix
    ./neovim.nix
    ./tmux.nix
    ./zsh.nix
  ] ++ (
    if system == "aarch64-darwin"
    then [ ./platforms/darwin.nix ]
    else [ ./platforms/linux.nix ]
  ) ++ (
    if lib.hasPrefix "aarch64" system
    then [ ./architectures/aarch64.nix ]
    else [ ./architectures/x86_64.nix ]
  );


  home.username = "moye";
  

  home.packages = with pkgs; (
    (import ./common.nix { inherit pkgs; })
  );

  home.file.".config/nvim" = {
    source = ../nvim;
    recursive = true;
  };

  home.file.".config/pass-git-helper/git-pass-mapping.ini" = {
    text = ''
      [github.com*]
      target=git/github.com
    '';
  };

  home.stateVersion = "24.05";
}
