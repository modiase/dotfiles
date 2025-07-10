{ pkgs }:

pkgs.mkShell {
  buildInputs = with pkgs; [
    bashInteractive
    git
    nix
  ];
}
