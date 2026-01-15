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
    litellm-proxy = {
      url = "path:./nix/nixpkgs/litellm-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-orchestrator = {
      url = "path:./nix/nixpkgs/llm-orchestrator";
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
      litellm-proxy,
      llm-orchestrator,
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

      iris = mkSystem {
        name = "iris";
        system = "aarch64-darwin";
        type = "darwin";
        os = "darwin";
        isFrontend = true;
        modules = [ ./systems/iris/configuration.nix ];
      };

      pallas = mkSystem {
        name = "pallas";
        system = "aarch64-darwin";
        type = "darwin";
        os = "darwin";
        isFrontend = true;
        manageRemotely = true;
        modules = [ ./systems/pallas/configuration.nix ];
      };

      hephaistos = mkSystem {
        name = "hephaistos";
        system = "aarch64-darwin";
        type = "darwin";
        os = "darwin";
        isFrontend = false;
        hostname = null;
        user = "moyeodiase";
        modules = [ ./systems/hephaistos/configuration.nix ];
        homeExtraModules = [
          {
            launchd.agents.ntfy-listen.enable = lib.mkForce false;
            programs.fish.loginShellInit = lib.mkBefore ''
              set -U hostname_override hephaistos
            '';
            home.file.".hammerspoon/init.lua".text = lib.mkForce ''
              hs.hotkey.bind({"cmd", "shift"}, "a", function() hs.application.launchOrFocus("Google Tasks") end)
              hs.hotkey.bind({"cmd", "shift"}, "b", function() hs.application.launchOrFocus("Google Chrome") end)
              hs.hotkey.bind({"cmd", "shift"}, "c", function() hs.application.launchOrFocus("Cider") end)
              hs.hotkey.bind({"cmd", "shift"}, "d", function() hs.application.launchOrFocus("Docs") end)
              hs.hotkey.bind({"cmd", "shift"}, "g", function() hs.application.launchOrFocus("Gemini") end)
              hs.hotkey.bind({"cmd", "shift"}, "h", function() hs.application.launchOrFocus("Google Chat") end)
              hs.hotkey.bind({"cmd", "shift"}, "k", function() hs.application.launchOrFocus("Google Calendar") end)
              hs.hotkey.bind({"cmd", "shift"}, "m", function() hs.application.launchOrFocus("Gmail") end)
              hs.hotkey.bind({"cmd", "shift"}, "t", function() hs.application.launchOrFocus("Ghostty") end)
              hs.hotkey.bind({"cmd", "shift"}, "u", function() hs.application.launchOrFocus("Youtube Music") end)
            '';
          }
        ];
      };

      herakles = mkSystem {
        name = "herakles";
        system = "x86_64-linux";
        type = "nixos";
        os = "nixos";
        manageRemotely = true;
        extraSpecialArgs = { inherit llm-server litellm-proxy llm-orchestrator; };
        modules = [
          ./systems/herakles/configuration.nix
          ./systems/herakles/hardware-configuration.nix
        ];
      };

      hermes = mkSystem {
        name = "hermes";
        system = "x86_64-linux";
        type = "nixos";
        os = "nixos";
        modules = [
          ./systems/hermes/configuration.nix
          ./systems/hermes/hardware-configuration.nix
        ];
      };

      hekate = mkSystem {
        name = "hekate";
        system = "aarch64-linux";
        type = "nixos";
        os = "nixos";
        modules = [ ./systems/hekate/configuration.nix ];
      };

      hestia = mkSystem {
        name = "hestia";
        system = "aarch64-linux";
        type = "nixos";
        os = "nixos";
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

      zeus = mkSystem {
        name = "zeus";
        system = "x86_64-linux";
        type = "nixos";
        os = "debian";
        user = "moyeodiase";
        homeDirectory = "/usr/local/google/home/moyeodiase";
        modules = [ ./systems/zeus/configuration.nix ];
      };
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
