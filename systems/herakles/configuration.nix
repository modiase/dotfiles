{
  config,
  lib,
  pkgs,
  authorizedKeyLists,
  commonNixSettings,
  llm-server,
  litellm-proxy,
  llm-orchestrator,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    commonNixSettings
    llm-server.nixosModules.default
    litellm-proxy.nixosModules.default
    llm-orchestrator.nixosModules.default
  ];

  config = {
    services.llm-server.enable = false;

    services.vllm.instances = {
      chat = {
        enable = true;
        model = "QuixiAI/Qwen3-30B-A3B-AWQ";
        port = 8001;
        gpuMemoryUtilization = 0.80;
        maxModelLen = 32768;
        maxNumSeqs = 64;
      };
      coder = {
        enable = true;
        model = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit";
        port = 8002;
        gpuMemoryUtilization = 0.80;
        maxModelLen = 32768;
        maxNumSeqs = 64;
      };
      embed = {
        enable = true;
        model = "Qwen/Qwen3-Embedding-0.6B";
        port = 8003;
        gpuMemoryUtilization = 0.15;
        maxModelLen = 8192;
        task = "embed";
      };
    };

    services.litellm-proxy = {
      enable = true;
      port = 4000;
      environmentFile = "/var/lib/litellm/env";
      settings = {
        model_list = [
          {
            model_name = "qwen-chat";
            litellm_params = {
              model = "openai/QuixiAI/Qwen3-30B-A3B-AWQ";
              api_base = "http://127.0.0.1:8001/v1";
              api_key = "not-needed";
            };
          }
          {
            model_name = "qwen-coder";
            litellm_params = {
              model = "openai/cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit";
              api_base = "http://127.0.0.1:8002/v1";
              api_key = "not-needed";
            };
          }
          {
            model_name = "qwen-embed";
            litellm_params = {
              model = "openai/Qwen/Qwen3-Embedding-0.6B";
              api_base = "http://127.0.0.1:8003/v1";
              api_key = "not-needed";
            };
          }
          {
            model_name = "sonnet";
            litellm_params = {
              model = "anthropic/claude-sonnet-4-5-20250929";
              api_key = "os.environ/ANTHROPIC_API_KEY";
            };
          }
          {
            model_name = "haiku";
            litellm_params = {
              model = "anthropic/claude-haiku-4-5-20251015";
              api_key = "os.environ/ANTHROPIC_API_KEY";
            };
          }
          {
            model_name = "gemini3";
            litellm_params = {
              model = "gemini/gemini-3-pro-preview";
              api_key = "os.environ/GEMINI_API_KEY";
            };
          }
          {
            model_name = "gemini-flash";
            litellm_params = {
              model = "gemini/gemini-2.5-flash-preview-05-20";
              api_key = "os.environ/GEMINI_API_KEY";
            };
          }
        ];
        litellm_settings = {
          num_retries = 2;
          request_timeout = 120;
        };
      };
    };

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    networking.hostName = "herakles";
    networking.networkmanager.enable = true;

    time.timeZone = "Europe/London";

    i18n.defaultLocale = "en_GB.UTF-8";

    users.users.moye = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "networkmanager"
        "docker"
      ];
      createHome = true;
      openssh.authorizedKeys.keys = authorizedKeyLists.moye;
    };

    security.sudo.extraRules = [
      {
        users = [ "moye" ];
        commands = [
          {
            command = "ALL";
            options = [
              "NOPASSWD"
              "SETENV"
            ];
          }
        ];
      }
    ];

    environment.systemPackages = with pkgs; [
      git
      jq
      nix-prefetch
      (pkgs.symlinkJoin {
        name = "nvitop-wrapped";
        paths = [ nvitop ];
        buildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/nvitop \
            --prefix LD_LIBRARY_PATH : "${config.hardware.nvidia.package}/lib"
        '';
      })
      vim
      wget
    ];

    services.openssh.enable = true;
    services.eternal-terminal.enable = true;

    services.avahi = {
      enable = true;
      nssmdns4 = true;
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    networking.firewall.enable = false;

    nixpkgs.config.allowUnfree = true;

    services.xserver.enable = true;
    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
      package = config.hardware.nvidia.package;
    };

    hardware.nvidia = {
      modesetting.enable = true;
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      nvidiaSettings = true;
    };

    nixpkgs.config.cudaSupport = true;

    hardware.nvidia-container-toolkit.enable = true;

    nix.settings = {
      max-jobs = 16;
      trusted-users = [ "moye" ];
      secret-key-files = [ "/etc/nix/signing-key.sec" ];
      post-build-hook = pkgs.writeShellScript "post-build-hook" ''
        set -eu
        set -f
        export IFS=' '

        for path in $OUT_PATHS; do
          ${pkgs.nix}/bin/nix store sign --key-file /etc/nix/signing-key.sec "$path"
        done
      '';
      substituters = [
        "https://cache.nixos.org"
        "https://cuda-maintainers.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkgKbtJrytuOoQqR5RQY="
        "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
      ];
    };

    system.stateVersion = "25.05";
    virtualisation.docker.enable = true;
  };
}
