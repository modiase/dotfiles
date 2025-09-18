{
  description = "Moyewa Odiase - Home Directory Config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      flake-utils,
      ...
    }@inputs:
    let
      username = "moye";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      homeConfigurations."${username}-x86_64-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
          overlays = [
            (self: super: {
              gpt-cli = super.callPackage ./nix/nixpkgs/gpt-cli { };
              codex-cli = super.callPackage ./nix/nixpkgs/codex-cli { };
              space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
              lato = super.callPackage ./nix/nixpkgs/lato { };
            })
          ];
        };
        extraSpecialArgs = {
          system = "x86_64-linux";
        };
        modules = [
          ./nix/home.nix
          {
            home.homeDirectory = "/home/${username}";
            home.stateVersion = "24.05";
          }
        ];
      };

      homeConfigurations."${username}-aarch64-linux" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-linux";
          config.allowUnfree = true;
          overlays = [
            (self: super: {
              gpt-cli = super.callPackage ./nix/nixpkgs/gpt-cli { };
              codex-cli = super.callPackage ./nix/nixpkgs/codex-cli { };
              space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
              lato = super.callPackage ./nix/nixpkgs/lato { };
            })
          ];
        };
        extraSpecialArgs = {
          system = "aarch64-linux";
        };
        modules = [
          ./nix/home.nix
          {
            home.homeDirectory = "/home/${username}";
            home.stateVersion = "24.05";
          }
        ];
      };

      homeConfigurations."${username}-aarch64-darwin" = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
          overlays = [
            (self: super: {
              gpt-cli = super.callPackage ./nix/nixpkgs/gpt-cli { };
              codex-cli = super.callPackage ./nix/nixpkgs/codex-cli { };
              space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
              lato = super.callPackage ./nix/nixpkgs/lato { };
            })
          ];
        };
        extraSpecialArgs = {
          system = "aarch64-darwin";
        };
        modules = [
          ./nix/home.nix
          {
            home.homeDirectory = "/Users/${username}";
            home.stateVersion = "24.05";
          }
        ];
      };

      darwinConfigurations."iris" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          overlays = [
            (self: super: {
              space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
              lato = super.callPackage ./nix/nixpkgs/lato { };
            })
          ];
        };
        modules = [
          ./systems/iris/configuration.nix
        ];
      };

      darwinConfigurations."pallas" = nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        pkgs = import nixpkgs {
          system = "aarch64-darwin";
          overlays = [
            (self: super: {
              space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
              lato = super.callPackage ./nix/nixpkgs/lato { };
            })
          ];
        };
        modules = [
          ./systems/pallas/configuration.nix
        ];
      };

      nixosConfigurations."herakles" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./systems/herakles/configuration.nix
          ./systems/herakles/hardware-configuration.nix
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
        ];
      };
    };
}
