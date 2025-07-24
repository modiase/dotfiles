ARG PLATFORM=amd64
FROM --platform=linux/${PLATFORM} nixos/nix:latest

RUN nix-channel --add https://nixos.org/channels/nixpkgs-unstable nixpkgs && \
    nix-channel --update && \
    nix-env -iA nixpkgs.neovim nixpkgs.nixfmt-rfc-style

WORKDIR /sandbox
RUN echo '{\
  description = "A development environment with Neovim";\
\
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";\
\
  outputs = { self, nixpkgs }:\
    let\
      forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];\
    in\
    {\
      devShells = forAllSystems (system: {\
        default = nixpkgs.legacyPackages.${system}.mkShell {\
          buildInputs = [\
            nixpkgs.legacyPackages.${system}.bashInteractive\
          ];\
        };\
      });\
    };\
}' > /sandbox/flake.nix && nixfmt /sandbox/flake.nix
