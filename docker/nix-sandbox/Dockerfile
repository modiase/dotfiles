FROM nixos/nix

RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs &&     nix-channel --update &&     nix-env -iA nixpkgs.neovim

