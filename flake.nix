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
    tk700-controller-dashboard = {
      url = "github:modiase/tk700-controller-dashboard";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-server = {
      url = "path:./nix/nixpkgs/llm-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      flake-utils,
      tk700-controller-dashboard,
      llm-server,
      ...
    }@inputs:
    let
      username = "moye";
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      lib = nixpkgs.lib;
      authorizedKeys = import ./nix/authorized-keys.nix;
      authorizedKeyLists = lib.mapAttrs (
        _: hostMap:
        let
          normalized = lib.mapAttrs (_: value: lib.toList value) hostMap;
        in
        lib.unique (lib.concatLists (lib.attrValues normalized))
      ) authorizedKeys;

      darwinFrontendServices =
        { pkgs, ... }:
        {
          environment.systemPackages = with pkgs; [
            yabai
            skhd
          ];

          fonts.packages = with pkgs; [
            nerd-fonts.iosevka
            space-grotesk
            lato
            aleo
          ];

          launchd.user.agents.yabai = {
            serviceConfig = {
              ProgramArguments = [ "${pkgs.yabai}/bin/yabai" ];
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/tmp/yabai.out.log";
              StandardErrorPath = "/tmp/yabai.err.log";
            };
          };

          launchd.user.agents.skhd = {
            serviceConfig = {
              ProgramArguments = [ "${pkgs.skhd}/bin/skhd" ];
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/tmp/skhd.out.log";
              StandardErrorPath = "/tmp/skhd.err.log";
            };
          };
        };

      commonNixSettings = {
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "root"
            "moye"
          ];
          trusted-public-keys = [
            "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
            "herakles-1:63/4Yp9uC4U7rQuVuHDKak+JgNfYolBhKqIs34ghF2M="
          ];
        };
      };

      heraklesBuildServer =
        hostName:
        { pkgs, ... }:
        {
          nix.distributedBuilds = true;
          nix.settings.builders-use-substitutes = true;
          nix.buildMachines = [
            {
              hostName = "herakles";
              sshUser = "moye";
              protocol = "ssh-ng";
              systems = [
                "x86_64-linux"
                "aarch64-linux"
              ];
              maxJobs = 8;
              speedFactor = 2;
              supportedFeatures = [
                "kvm"
                "big-parallel"
              ];
            }
          ];
        };
      darwinCommonModules = [ ];

      sharedOverlays = [ ];

      fontOverlays = [
        (self: super: {
          space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
          lato = super.callPackage ./nix/nixpkgs/lato { };
          aleo = super.callPackage ./nix/nixpkgs/aleo { };
        })
      ];

      mkSystem =
        {
          name,
          system,
          type,
          modules ? [ ],
          extraSpecialArgs ? { },
          extraOverlays ? [ ],
          isFrontend ? false,
          manageRemotely ? false,
        }:
        let
          isDarwin = type == "darwin";
          systemOverlays =
            sharedOverlays ++ lib.optionals (isDarwin && isFrontend) fontOverlays ++ extraOverlays;
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = systemOverlays;
          };

          baseSpecialArgs = {
            inherit
              authorizedKeys
              authorizedKeyLists
              commonNixSettings
              ;
          }
          // lib.optionalAttrs isDarwin {
            inherit darwinFrontendServices heraklesBuildServer;
          }
          // extraSpecialArgs;

          dotfilesModule =
            { lib, ... }:
            {
              options.dotfiles = {
                manageRemotely = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                isFrontend = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
              config.dotfiles = {
                inherit manageRemotely isFrontend;
              };
            };
        in
        if isDarwin then
          nix-darwin.lib.darwinSystem {
            inherit system pkgs;
            specialArgs = baseSpecialArgs;
            modules = [ dotfilesModule ] ++ darwinCommonModules ++ modules;
          }
        else
          nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = baseSpecialArgs;
            modules = [
              dotfilesModule
              { nixpkgs.overlays = systemOverlays; }
            ]
            ++ modules;
          };

      mkHomeConfig =
        {
          name,
          system,
          isFrontend ? false,
        }:
        let
          isDarwin = lib.hasSuffix "darwin" system;
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = sharedOverlays;
          };
          extraSpecialArgs = { inherit isFrontend; };
          modules = [
            ./nix/home.nix
            (if isDarwin then ./nix/platforms/darwin.nix else ./nix/platforms/linux.nix)
            {
              home.homeDirectory = if isDarwin then "/Users/${username}" else "/home/${username}";
              home.stateVersion = "24.05";
            }
          ];
        };
    in
    {
      homeConfigurations."${username}-iris" = mkHomeConfig {
        name = "iris";
        system = "aarch64-darwin";
        isFrontend = true;
      };

      homeConfigurations."${username}-pallas" = mkHomeConfig {
        name = "pallas";
        system = "aarch64-darwin";
        isFrontend = true;
      };

      homeConfigurations."${username}-herakles" = mkHomeConfig {
        name = "herakles";
        system = "x86_64-linux";
      };

      homeConfigurations."${username}-hermes" = mkHomeConfig {
        name = "hermes";
        system = "x86_64-linux";
      };

      homeConfigurations."${username}-hekate" = mkHomeConfig {
        name = "hekate";
        system = "aarch64-linux";
      };

      homeConfigurations."${username}-hestia" = mkHomeConfig {
        name = "hestia";
        system = "aarch64-linux";
      };

      darwinConfigurations."iris" = mkSystem {
        name = "iris";
        system = "aarch64-darwin";
        type = "darwin";
        isFrontend = true;
        modules = [ ./systems/iris/configuration.nix ];
      };

      darwinConfigurations."pallas" = mkSystem {
        name = "pallas";
        system = "aarch64-darwin";
        type = "darwin";
        isFrontend = true;
        manageRemotely = true;
        modules = [ ./systems/pallas/configuration.nix ];
      };

      nixosConfigurations."herakles" = mkSystem {
        name = "herakles";
        system = "x86_64-linux";
        type = "nixos";
        manageRemotely = true;
        extraSpecialArgs = { inherit llm-server; };
        modules = [
          ./systems/herakles/configuration.nix
          ./systems/herakles/hardware-configuration.nix
        ];
      };

      nixosConfigurations."hermes" = mkSystem {
        name = "hermes";
        system = "x86_64-linux";
        type = "nixos";
        modules = [
          ./systems/hermes/configuration.nix
          ./systems/hermes/hardware-configuration.nix
        ];
      };

      nixosConfigurations."hekate" = mkSystem {
        name = "hekate";
        system = "aarch64-linux";
        type = "nixos";
        modules = [ ./systems/hekate/configuration.nix ];
      };

      nixosConfigurations."hestia" = mkSystem {
        name = "hestia";
        system = "aarch64-linux";
        type = "nixos";
        manageRemotely = true;
        extraSpecialArgs = { inherit heraklesBuildServer; };
        extraOverlays = [
          (final: prev: {
            tk700-controller-dashboard =
              tk700-controller-dashboard.packages.${prev.stdenv.hostPlatform.system}.default.overrideAttrs
                (old: {
                  basePath = "/projector/";
                  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.pnpm ];
                  buildPhase = ''
                    runHook preBuild
                    export HOME=$TMPDIR

                    export BASE_PATH="/projector/"
                    ${prev.pnpm}/bin/pnpm run build

                    ${prev.bun}/bin/bun build src/index.ts \
                      --target=bun \
                      --outfile=server.js \
                      --minify

                    runHook postBuild
                  '';
                });
          })
        ];
        modules = [ ./systems/hestia/configuration.nix ];
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        deployPythonEnv = pkgs.python312.withPackages (
          ps: with ps; [
            click
            loguru
            inquirer
            google-cloud-secret-manager
            google-cloud-storage
            crc32c
          ]
        );

        build-hekate = pkgs.writeShellApplication {
          name = "build-hekate";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
            pkgs.pv
          ];
          text = ''
            export PYTHONPATH="${./nix/nixpkgs/pyutils}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./systems/hekate/build/image} "$@"
          '';
        };

        build-hermes = pkgs.writeShellApplication {
          name = "build-hermes";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
          ];
          text = ''
            export PYTHONPATH="${./nix/nixpkgs/pyutils}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./systems/hermes/build/image} "$@"
          '';
        };

        build-hestia = pkgs.writeShellApplication {
          name = "build-hestia";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
          ];
          text = ''
            export PYTHONPATH="${./nix/nixpkgs/pyutils}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./systems/hestia/build/image} "$@"
          '';
        };

        shellutils = pkgs.callPackage ./nix/nixpkgs/shellutils { };
      in
      {
        packages = {
          inherit build-hekate build-hermes build-hestia;
          inherit (shellutils) hook-utils logging-utils build-gce-nixos-image;
        };

        shellutils = shellutils;

        apps = {
          build-hekate = {
            type = "app";
            program = "${build-hekate}/bin/build-hekate";
          };
          build-hermes = {
            type = "app";
            program = "${build-hermes}/bin/build-hermes";
          };
          build-hestia = {
            type = "app";
            program = "${build-hestia}/bin/build-hestia";
          };
        };
      }
    );
}
