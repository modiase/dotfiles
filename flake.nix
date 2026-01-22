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
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
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
      nix-homebrew,
      homebrew-core,
      homebrew-cask,
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
          fonts.packages = with pkgs; [
            nerd-fonts.iosevka
            space-grotesk
            lato
            aleo
          ];
        };

      commonNixSettings = {
        nix.optimise.automatic = true;
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
        nix.registry.nixpkgs.flake = inputs.nixpkgs;
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
      darwinCommonModules = [
        nix-homebrew.darwinModules.nix-homebrew
      ];

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
          os,
          modules ? [ ],
          extraSpecialArgs ? { },
          extraOverlays ? [ ],
          isFrontend ? false,
          manageRemotely ? false,
          manageSystem ? null,
          manageHome ? true,
          hostname ? name,
          user ? username,
          homeDirectory ? null,
          homeExtraModules ? [ ],
          mkBuildImage ? null,
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
            inherit
              darwinFrontendServices
              heraklesBuildServer
              homebrew-core
              homebrew-cask
              ;
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
                os = lib.mkOption {
                  type = lib.types.enum [
                    "darwin"
                    "nixos"
                    "debian"
                    "other"
                  ];
                };
                manageSystem = lib.mkOption {
                  type = lib.types.bool;
                };
                manageHome = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
              };
              config.dotfiles = {
                inherit
                  manageRemotely
                  isFrontend
                  os
                  manageHome
                  ;
                manageSystem = if manageSystem != null then manageSystem else (os == "darwin" || os == "nixos");
              };
            };

          hostnameModule = lib.optionalAttrs (hostname != null) (
            if isDarwin then
              {
                networking.hostName = hostname;
                networking.computerName = hostname;
                networking.localHostName = hostname;
              }
            else
              {
                networking.hostName = hostname;
              }
          );

          systemConfig =
            if isDarwin then
              nix-darwin.lib.darwinSystem {
                inherit system pkgs;
                specialArgs = baseSpecialArgs;
                modules = [
                  dotfilesModule
                  hostnameModule
                ]
                ++ darwinCommonModules
                ++ modules;
              }
            else
              nixpkgs.lib.nixosSystem {
                inherit system;
                specialArgs = baseSpecialArgs;
                modules = [
                  dotfilesModule
                  hostnameModule
                  { nixpkgs.overlays = systemOverlays; }
                ]
                ++ modules;
              };

          homeConfig = mkHomeConfig {
            inherit
              name
              system
              isFrontend
              user
              homeDirectory
              ;
            extraModules = homeExtraModules;
          };
        in
        {
          systemAttr = {
            "${name}" = systemConfig;
          };
          homeAttr = {
            "${user}-${name}" = homeConfig;
          };
          inherit name mkBuildImage;
        };

      mkHomeConfig =
        {
          name,
          system,
          isFrontend ? false,
          user ? username,
          homeDirectory ? null,
          extraModules ? [ ],
        }:
        let
          isDarwin = lib.hasSuffix "darwin" system;
          defaultHomeDir = if isDarwin then "/Users/${user}" else "/home/${user}";
        in
        home-manager.lib.homeManagerConfiguration {
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = sharedOverlays;
          };
          extraSpecialArgs = { inherit isFrontend user; };
          modules = [
            ./nix/home.nix
            (if isDarwin then ./nix/platforms/darwin.nix else ./nix/platforms/linux.nix)
            {
              home.homeDirectory = if homeDirectory != null then homeDirectory else defaultHomeDir;
              home.stateVersion = "24.05";
            }
          ]
          ++ extraModules;
        };

      iris = mkSystem (import ./systems/iris { });
      pallas = mkSystem (import ./systems/pallas { });
      hephaistos = mkSystem (import ./systems/hephaistos { inherit lib; });
      herakles = mkSystem (import ./systems/herakles);
      hermes = mkSystem (import ./systems/hermes { });
      hekate = mkSystem (import ./systems/hekate { });
      hestia = mkSystem (
        import ./systems/hestia { inherit heraklesBuildServer tk700-controller-dashboard; }
      );
      zeus = mkSystem (import ./systems/zeus { inherit lib; });
    in
    {
      darwinConfigurations = iris.systemAttr // pallas.systemAttr // hephaistos.systemAttr;

      nixosConfigurations =
        herakles.systemAttr
        // hermes.systemAttr
        // hekate.systemAttr
        // hestia.systemAttr
        // zeus.systemAttr;

      homeConfigurations =
        iris.homeAttr
        // pallas.homeAttr
        // hephaistos.homeAttr
        // herakles.homeAttr
        // hermes.homeAttr
        // hekate.homeAttr
        // hestia.homeAttr
        // zeus.homeAttr;
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

        buildImageArgs = {
          inherit pkgs deployPythonEnv;
          repoRoot = ./.;
        };

        allSystems = [
          hekate
          hermes
          hestia
        ];
        buildableSystems = builtins.filter (s: s.mkBuildImage or null != null) allSystems;
        buildImageScripts = builtins.listToAttrs (
          map (s: {
            name = s.name;
            value = s.mkBuildImage buildImageArgs;
          }) buildableSystems
        );
        buildableNames = map (s: s.name) buildableSystems;

        build-system-image = pkgs.writeShellApplication {
          name = "build-system-image";
          runtimeInputs = [ pkgs.gum ];
          text =
            let
              cases = lib.concatStringsSep "\n" (
                map (
                  s: ''${s.name}) exec ${buildImageScripts.${s.name}}/bin/build-${s.name}-image "$@" ;;''
                ) buildableSystems
              );
              systemList = lib.concatStringsSep " " buildableNames;
              systemChoices = lib.concatStringsSep "\\n" buildableNames;
            in
            ''
              if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
                echo "Usage: build-system-image [system] [args...]"
                echo "Available systems: ${systemList}"
                echo "If no system specified, opens interactive selector."
                exit 0
              fi

              system="''${1:-}"
              if [[ -z "$system" ]]; then
                system=$(echo -e "${systemChoices}" | gum choose --header "Select system to build:")
                [[ -z "$system" ]] && exit 0
              else
                shift
              fi

              case "$system" in
                ${cases}
                *)
                  echo "Unknown system: $system"
                  echo "Available systems: ${systemList}"
                  exit 1 ;;
              esac
            '';
        };

        shellutils = pkgs.callPackage ./nix/nixpkgs/shellutils { };
      in
      {
        packages = {
          inherit build-system-image;
          inherit (shellutils) hook-utils logging-utils build-gce-nixos-image;
        }
        // buildImageScripts;

        shellutils = shellutils;

        apps = {
          build-system-image = {
            type = "app";
            program = "${build-system-image}/bin/build-system-image";
          };
        };
      }
    );
}
