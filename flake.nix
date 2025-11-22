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
      lib = nixpkgs.lib;
      authorizedKeys = import ./systems/authorized-keys.nix;
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
        (
          { pkgs, ... }:
          {
            environment.systemPackages = [ pkgs.xquartz ];

            launchd.daemons."org.nixos.xquartz.privileged_startx" = {
              serviceConfig = {
                Label = "org.nixos.xquartz.privileged_startx";
                ProgramArguments = [
                  "${pkgs.xquartz}/libexec/privileged_startx"
                  "-d"
                  "${pkgs.xquartz}/etc/X11/xinit/privileged_startx.d"
                ];
                MachServices."org.nixos.xquartz.privileged_startx" = true;
                TimeOut = 120;
                EnableTransactions = true;
              };
            };

            launchd.user.agents."org.nixos.xquartz.startx" = {
              serviceConfig = {
                Label = "org.nixos.xquartz.startx";
                ProgramArguments = [
                  "${pkgs.xquartz}/libexec/launchd_startx"
                  "${pkgs.xquartz}/bin/startx"
                  "--"
                  "${pkgs.xquartz}/bin/Xquartz"
                ];
                ServiceIPC = true;
                EnableTransactions = true;
                Sockets."org.nixos.xquartz:0".SecureSocketWithKey = "DISPLAY";
                EnvironmentVariables.FONTCONFIG_FILE = "${pkgs.xquartz}/etc/X11/fonts.conf";
              };
            };
          }
        )
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
        specialArgs = {
          inherit
            authorizedKeys
            authorizedKeyLists
            commonNixSettings
            darwinFrontendServices
            heraklesBuildServer
            ;
        };
        modules = darwinCommonModules ++ [
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
        specialArgs = {
          inherit
            authorizedKeys
            authorizedKeyLists
            commonNixSettings
            darwinFrontendServices
            heraklesBuildServer
            ;
        };
        modules = darwinCommonModules ++ [
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
        specialArgs = { inherit authorizedKeys authorizedKeyLists commonNixSettings; };
      };

      nixosConfigurations."hermes" = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./systems/hermes/configuration.nix
          ./systems/hermes/hardware-configuration.nix
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
            nixpkgs.overlays = [ ];
          }
        ];
        specialArgs = { inherit authorizedKeys authorizedKeyLists commonNixSettings; };
      };

      nixosConfigurations."hekate" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./systems/hekate/configuration.nix
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
        ];
        specialArgs = { inherit authorizedKeys authorizedKeyLists commonNixSettings; };
      };

      nixosConfigurations."hestia" = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          ./systems/hestia/configuration.nix
          {
            nix.settings.experimental-features = [
              "nix-command"
              "flakes"
            ];
          }
        ];
        specialArgs = {
          inherit
            authorizedKeys
            authorizedKeyLists
            commonNixSettings
            heraklesBuildServer
            ;
        };
      };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Python environment for deployment tools
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

        # Build hekate app
        build-hekate = pkgs.writeShellApplication {
          name = "build-hekate";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
            pkgs.pv
          ];
          text = ''
            export PYTHONPATH="${./lib}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./lib/build-hekate.py} "$@"
          '';
        };

        # Build hermes app
        build-hermes = pkgs.writeShellApplication {
          name = "build-hermes";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
          ];
          text = ''
            export PYTHONPATH="${./lib}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./lib/build-hermes.py} "$@"
          '';
        };

        build-hestia = pkgs.writeShellApplication {
          name = "build-hestia";
          runtimeInputs = [
            deployPythonEnv
            pkgs.google-cloud-sdk
          ];
          text = ''
            export PYTHONPATH="${./lib}:''${PYTHONPATH:-}"
            export REPO_ROOT="${./.}"
            exec ${deployPythonEnv}/bin/python ${./lib/build-hestia.py} "$@"
          '';
        };
      in
      {
        packages = {
          inherit build-hekate build-hermes build-hestia;
        };

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
