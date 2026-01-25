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
      flake-utils,
      home-manager,
      homebrew-cask,
      homebrew-core,
      nix-darwin,
      nix-homebrew,
      nixpkgs,
      tk700-controller-dashboard,
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
            aleo
            lato
            nerd-fonts.iosevka
            space-grotesk
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
        nix.registry.dotfiles.flake = self;
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
          aleo = super.callPackage ./nix/nixpkgs/aleo { };
          lato = super.callPackage ./nix/nixpkgs/lato { };
          space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
        })
      ];

      mkSystem =
        {
          name,
          os,
          system,
          type,
          extraOverlays ? [ ],
          extraSpecialArgs ? { },
          homeDirectory ? null,
          homeExtraModules ? [ ],
          hostname ? name,
          isFrontend ? false,
          manageHome ? true,
          manageRemotely ? false,
          manageSystem ? null,
          mkBuildImage ? null,
          modules ? [ ],
          user ? username,
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
              homeDirectory
              isFrontend
              name
              system
              user
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
          extraModules ? [ ],
          homeDirectory ? null,
          isFrontend ? false,
          user ? username,
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

      hekate = mkSystem (import ./systems/hekate { });
      herakles = mkSystem (import ./systems/herakles);
      hephaistos = mkSystem (import ./systems/hephaistos { inherit lib; });
      hermes = mkSystem (import ./systems/hermes { });
      hestia = mkSystem (
        import ./systems/hestia { inherit heraklesBuildServer tk700-controller-dashboard; }
      );
      iris = mkSystem (import ./systems/iris { });
      pallas = mkSystem (import ./systems/pallas { });
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
            crc32c
            google-cloud-secret-manager
            google-cloud-storage
            inquirer
            loguru
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

        claude-code = pkgs.callPackage ./nix/nixpkgs/claude-code/package.nix { };
        cve-scanner = pkgs.callPackage ./nix/nixpkgs/cve-scanner { };
        secrets = pkgs.callPackage ./nix/nixpkgs/secrets { };
        shellutils = pkgs.callPackage ./nix/nixpkgs/shellutils { };
        swiftdialog = pkgs.callPackage ./nix/nixpkgs/swiftdialog { };
      in
      {
        packages = {
          inherit
            build-system-image
            claude-code
            cve-scanner
            secrets
            ;
          inherit (shellutils) hook-utils logging-utils build-gce-nixos-image;
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin { inherit swiftdialog; };

        shellutils = shellutils;

        apps = {
          build-system-image = {
            type = "app";
            program = "${build-system-image}/bin/build-system-image";
          };
          secrets = {
            type = "app";
            program = "${secrets}/bin/secrets";
          };
          cve-scanner = {
            type = "app";
            program = "${cve-scanner}/bin/cve-scanner";
          };
        }
        // lib.optionalAttrs pkgs.stdenv.isDarwin {
          swiftdialog = {
            type = "app";
            program = "${swiftdialog}/bin/dialog";
          };
        };
      }
    );
}
