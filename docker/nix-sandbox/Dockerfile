ARG PLATFORM=amd64
FROM --platform=linux/${PLATFORM} nixos/nix:latest

RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --update && \
    nix-env -iA nixpkgs.neovim

WORKDIR /sandbox
RUN echo '{\
  description = "A development environment with Neovim";\
\
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";\
\
  outputs = { self, nixpkgs }:\
    let\
      system = if builtins.currentSystem == "x86_64-linux" then "x86_64-linux" else "aarch64-linux";\
      pkgs = nixpkgs.legacyPackages.${system};\
    in\
    {\
      devShells.${system}.default = pkgs.mkShell {\
        buildInputs = [\
          pkgs.bashInteractive\
        ];\
      };\
    };\
}' > /sandbox/flake.nix

