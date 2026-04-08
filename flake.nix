{
  description = "Configuration, code and infrastructure";

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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
      sops-nix,
      tk700-controller-dashboard,
      ...
    }@inputs:
    let
      username = "moye";
      inherit (nixpkgs) lib;
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
            # keep-sorted start
            aleo
            lato
            nerd-fonts.iosevka
            space-grotesk
            # keep-sorted end
          ];
        };

      commonNixSettings = {
        nix = {
          optimise.automatic = true;
          settings = {
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
          registry.nixpkgs.flake = inputs.nixpkgs;
          registry.dotfiles.flake = self;
        };
      };

      heraklesBuildServer = _: {
        nix = {
          distributedBuilds = true;
          settings.builders-use-substitutes = true;
          buildMachines = [
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
      };
      darwinCommonModules = [
        nix-homebrew.darwinModules.nix-homebrew
      ];

      # TODO: remove once nixos-unstable advances past 2026-04-03.
      # nixos-unstable is stuck at 2026-04-01; claude-code 2.1.88 was yanked
      # from npm (404). Pin to a nixpkgs master commit with 2.1.92.
      nixpkgs-claude-code = builtins.fetchTarball {
        url = "https://github.com/NixOS/nixpkgs/archive/a366415aa31aaba86de150bc5002cedd27bd1c95.tar.gz";
        sha256 = "2ZVZ8QGj6DO18/rDkx2MijEWrTrD31BMZgL/zGOIXwk=";
      };

      sharedOverlays = [
        # TODO: remove once nixos-unstable advances past 2026-04-03 (see above)
        (final: _: {
          inherit
            (
              (import nixpkgs-claude-code {
                inherit (final) system;
                config.allowUnfree = true;
              })
            )
            claude-code
            ;
        })
        (_: super: {
          aleo = super.callPackage ./nix/nixpkgs/aleo { };
          gemini-nvim-ide-bridge = super.callPackage ./nix/nixpkgs/gemini-cli/scripts/gemini-nvim-ide-bridge {
            tmuxNvimSelect = super.callPackage ./nix/nixpkgs/tmux-nvim { };
            devlogsLibSrc = ./nix/nixpkgs/devlogs-lib;
          };
          lato = super.callPackage ./nix/nixpkgs/lato { };
          nvim-mcp = super.callPackage ./nix/nixpkgs/nvim-mcp { };
          space-grotesk = super.callPackage ./nix/nixpkgs/space-grotesk { };
          viddy = super.viddy.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/components/home.rs \
                --replace-fail 'Constraint::Length(32)]).areas(footer);' \
                               'Constraint::Length(0)]).areas(footer);'
            '';
          });
        })
      ];

      fontOverlays = [ ];

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
          isDev ? false,
          manageHome ? true,
          manageRemotely ? false,
          manageSystem ? null,
          mkBuildImage ? null,
          modules ? [ ],
          user ? username,
        }:
        let
          isDarwin = type == "darwin";
          systemOverlays = sharedOverlays ++ lib.optionals (isDarwin && isDev) fontOverlays ++ extraOverlays;
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
                isDev = lib.mkOption {
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
                  isDev
                  os
                  manageHome
                  ;
                manageSystem = if manageSystem != null then manageSystem else (os == "darwin" || os == "nixos");
              };
            };

          hostnameModule = lib.optionalAttrs (hostname != null) (
            if isDarwin then
              {
                networking = {
                  hostName = hostname;
                  computerName = hostname;
                  localHostName = hostname;
                };
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
              isDev
              system
              user
              ;
            extraModules = homeExtraModules;
          };
        in
        {
          inherit
            name
            type
            mkBuildImage
            systemConfig
            homeConfig
            ;
          homeKey = "${user}-${name}";
        };

      mkHomeConfig =
        {
          system,
          extraModules ? [ ],
          homeDirectory ? null,
          isDev ? false,
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
          extraSpecialArgs = { inherit isDev user; };
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

      systemConfigurations = {
        hekate = {
          type = "nixos";
          config = import ./systems/hekate { inherit sops-nix; };
        };
        hekate-debug = {
          type = "nixos";
          config =
            let
              base = import ./systems/hekate { inherit sops-nix; };
            in
            base // { modules = base.modules ++ [ { hekate.debugMode = true; } ]; };
        };
        hekate-vm = {
          type = "nixos";
          config = import ./systems/hekate/test-harness/vm.nix { inherit sops-nix; };
        };
        herakles = {
          type = "nixos";
          config = import ./systems/herakles;
        };
        hephaistos = {
          type = "darwin";
          user = "moyeodiase";
          config = import ./systems/hephaistos { inherit lib fontOverlays; };
        };
        hermes = {
          type = "nixos";
          config = import ./systems/hermes { };
        };
        hermes-vm = {
          type = "nixos";
          config = import ./systems/hermes/test-harness/vm.nix { };
        };
        hestia = {
          type = "nixos";
          config = import ./systems/hestia {
            inherit heraklesBuildServer tk700-controller-dashboard sops-nix;
          };
        };
        iris = {
          type = "darwin";
          config = import ./systems/iris { };
        };
        pallas = {
          type = "darwin";
          config = import ./systems/pallas { };
        };
        zeus = {
          type = "nixos";
          user = "moyeodiase";
          config = import ./systems/zeus { inherit lib; };
        };
      };

      evaluateSystemConfig = def: mkSystem def.config;
    in
    {
      darwinConfigurations = lib.mapAttrs (_: def: (evaluateSystemConfig def).systemConfig) (
        lib.filterAttrs (_: def: def.type == "darwin") systemConfigurations
      );

      nixosConfigurations = lib.mapAttrs (_: def: (evaluateSystemConfig def).systemConfig) (
        lib.filterAttrs (_: def: def.type == "nixos") systemConfigurations
      );

      homeConfigurations = lib.mapAttrs' (
        name: def: lib.nameValuePair "${def.user or username}-${name}" (evaluateSystemConfig def).homeConfig
      ) systemConfigurations;
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

        allSystems = map (name: evaluateSystemConfig systemConfigurations.${name}) [
          "hekate"
          "hermes"
          "hestia"
        ];
        buildableSystems = builtins.filter (s: s.mkBuildImage or null != null) allSystems;
        buildImageScripts = builtins.listToAttrs (
          map (s: {
            inherit (s) name;
            value = s.mkBuildImage buildImageArgs;
          }) buildableSystems
        );
        buildableNames = map (s: s.name) buildableSystems;

        build-system-image = pkgs.writeShellApplication {
          name = "build-system-image";
          runtimeInputs = [ pkgs.gum ];
          meta.description = "Interactive builder for NixOS system images";
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

        security-scan = pkgs.callPackage ./nix/nixpkgs/security-scan { };
        derive-age-key = pkgs.callPackage ./nix/nixpkgs/derive-age-key { };
        secrets = pkgs.callPackage ./nix/nixpkgs/secrets { };
        shellutils = pkgs.callPackage ./nix/nixpkgs/shellutils { };
      in
      {
        packages = {
          inherit
            build-system-image
            security-scan
            derive-age-key
            secrets
            ;
          inherit (shellutils) hook-utils logging-utils build-gce-nixos-image;
          claude-code =
            let
              devlogsLib = pkgs.callPackage ./nix/nixpkgs/devlogs-lib { };
              generateAgentsMd = pkgs.writeShellApplication {
                name = "generate-agents-md";
                runtimeInputs = [ pkgs.python3 ];
                text = ''
                  export PYTHONPATH="${devlogsLib.python}/lib:''${PYTHONPATH:-}"
                  export DEVLOGS_COMPONENT="generate-agents-md"
                  export AGENTS_SECTIONS_DIR="${./nix/nixpkgs/agents-config/sections}"
                  cond_args=""
                  if command -v nix >/dev/null 2>&1; then cond_args+=" --condition nix=true"; else cond_args+=" --condition nix=false"; fi
                  # shellcheck disable=SC2086
                  exec python3 ${./nix/nixpkgs/agents-config/generate-agents-md.py} $cond_args "$@"
                '';
              };
            in
            import ./nix/nixpkgs/claude-code/wrapper.nix {
              inherit pkgs generateAgentsMd;
              claudeCodePkg =
                (import nixpkgs {
                  inherit system;
                  config.allowUnfree = true;
                }).claude-code;
            };
        };

        inherit shellutils;

        apps = {
          build-system-image = {
            type = "app";
            program = "${build-system-image}/bin/build-system-image";
            description = "Interactive builder for NixOS system images";
          };
          security-scan = {
            type = "app";
            program = "${security-scan}/bin/security-scan";
            description = "Security vulnerability scanner with NVD API integration";
          };
          secrets = {
            type = "app";
            program = "${secrets}/bin/secrets";
            description = "Secrets management with multiple backends and encryption";
          };
        };
      }
    );
}
