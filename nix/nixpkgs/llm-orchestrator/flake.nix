{
  description = "vLLM Multi-Model Orchestrator";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkPackages =
        system: cfg:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            config.cudaSupport = true;
          };

          lmcache = pkgs.python312Packages.buildPythonPackage rec {
            pname = "lmcache";
            version = "0.3.12";
            pyproject = true;

            src = pkgs.fetchPypi {
              inherit pname version;
              hash = "sha256-L/iN1o4bBkQ3c1OG3UdZ5zx27xwBvSkDDaJgwTXaywc=";
            };

            build-system = with pkgs.python312Packages; [
              setuptools
              setuptools-scm
            ];

            nativeBuildInputs = [
              pkgs.cudaPackages.cudatoolkit
              pkgs.cudaPackages.cuda_nvcc
              pkgs.gcc
              pkgs.python312Packages.pythonRelaxDepsHook
            ];

            pythonRelaxDeps = [ "torch" ];

            postPatch = ''
              substituteInPlace setup.py --replace-quiet 'torch==' 'torch>='
              substituteInPlace pyproject.toml --replace-quiet 'torch==' 'torch>=' || true
            '';

            buildInputs = [
              pkgs.cudaPackages.cudatoolkit
              pkgs.cudaPackages.cudnn
            ];

            preBuild = ''
              export CUDA_HOME=${pkgs.cudaPackages.cudatoolkit}
              export PATH="${pkgs.cudaPackages.cuda_nvcc}/bin:$PATH"
              export TORCH_CUDA_ARCH_LIST="8.6"
            '';

            dependencies = with pkgs.python312Packages; [
              aiofile
              aiofiles
              aiohttp
              fastapi
              httptools
              httpx
              msgspec
              numpy
              prometheus-client
              psutil
              py-cpuinfo
              pyyaml
              pyzmq
              redis
              safetensors
              sortedcontainers
              torch
              transformers
              uvicorn
            ];

            pythonImportsCheck = [ "lmcache" ];
            doCheck = false;
            dontCheckRuntimeDeps = true;
          };

          pythonEnv = pkgs.python312.withPackages (
            ps: with ps; [
              (pkgs.python312Packages.vllm.overridePythonAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  [ -f setup.py ] && sed -i 's/-j=[0-9]/-j=4/g' setup.py
                '';

                preBuild = (old.preBuild or "") + ''
                  export CMAKE_BUILD_PARALLEL_LEVEL=4
                  export MAX_JOBS=4
                  export NIX_BUILD_CORES=4
                '';
              }))
              fastapi
              huggingface-hub
              lmcache
              pydantic
              uvicorn
              uvloop
            ]
          );

          cudaHome = pkgs.cudaPackages.cudatoolkit;
          gcc = pkgs.gcc;
          libPath = "${cudaHome}/lib:${pkgs.cudaPackages.cudnn}/lib";
          nvcc = pkgs.cudaPackages.cuda_nvcc;

          orchestratorDir = ./.; # Directory containing orchestrator.py and model_manager.py

          serve-script = pkgs.writeShellScriptBin "serve" ''
            set -e
            export CUDA_HOME=${cudaHome}
            export HF_HOME="''${HF_HOME:-$HOME/huggingface}"
            export LD_LIBRARY_PATH=${libPath}:''${LD_LIBRARY_PATH:-}
            export PATH="${nvcc}/bin:${gcc}/bin:''${PATH}"
            export TRITON_CACHE_DIR="''${VLLM_CACHE_ROOT}/triton"
            export VLLM_CACHE_ROOT="''${VLLM_CACHE_ROOT:-$HOME/vllm}"

            mkdir -p "$HF_HOME" "$VLLM_CACHE_ROOT" "$TRITON_CACHE_DIR"

            cd ${orchestratorDir}
            exec ${pythonEnv}/bin/python orchestrator.py
          '';

          service-download-script = pkgs.writeShellScriptBin "llm-orchestrator-download" ''
            set -e
            if [ "$EUID" -ne 0 ]; then
               echo "Error: This script must be run as root (sudo) to write to the service directory."
               exit 1
            fi

            CHAT_MODEL="''${CHAT_MODEL:-cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit}"
            EMBED_MODEL="''${EMBED_MODEL:-Qwen/Qwen3-Embedding-0.6B}"
            SERVICE_HOME="/var/lib/llm-orchestrator"
            SERVICE_USER="llm-orchestrator"

            echo "Downloading chat model '$CHAT_MODEL'..."
            sudo -u "$SERVICE_USER" \
              env HF_HOME="$SERVICE_HOME/huggingface" \
              ${pythonEnv}/bin/hf download "$CHAT_MODEL" --cache-dir "$SERVICE_HOME/huggingface"

            echo "Downloading embed model '$EMBED_MODEL'..."
            sudo -u "$SERVICE_USER" \
              env HF_HOME="$SERVICE_HOME/huggingface" \
              ${pythonEnv}/bin/hf download "$EMBED_MODEL" --cache-dir "$SERVICE_HOME/huggingface"

            echo "Download complete."
          '';

          service-start-script = pkgs.writeShellScriptBin "llm-orchestrator-start" ''
            set -e
            echo "Enabling and starting llm-orchestrator..."
            sudo systemctl reset-failed llm-orchestrator || true
            sudo systemctl enable --now llm-orchestrator
            sudo systemctl status llm-orchestrator --no-pager
          '';

          service-stop-script = pkgs.writeShellScriptBin "llm-orchestrator-stop" ''
            set -e
            echo "Stopping and disabling llm-orchestrator..."
            sudo systemctl disable --now llm-orchestrator
            sudo systemctl status llm-orchestrator --no-pager || true
          '';

          service-restart-script = pkgs.writeShellScriptBin "llm-orchestrator-restart" ''
            set -e
            echo "Restarting llm-orchestrator..."
            sudo systemctl reset-failed llm-orchestrator || true
            sudo systemctl restart llm-orchestrator
            sudo systemctl status llm-orchestrator --no-pager
          '';

          service-status-script = pkgs.writeShellScriptBin "llm-orchestrator-status" ''
            set -e
            echo "=== Service Status ==="
            systemctl status llm-orchestrator --no-pager || echo "Stopped (or not loaded)"

            CHAT_MODEL="''${CHAT_MODEL:-cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit}"
            CHAT_MODEL_DIR="$SERVICE_HOME/huggingface/models--$(echo $CHAT_MODEL | sed 's/\//--/g')"
            EMBED_MODEL="''${EMBED_MODEL:-Qwen/Qwen3-Embedding-0.6B}"
            EMBED_MODEL_DIR="$SERVICE_HOME/huggingface/models--$(echo $EMBED_MODEL | sed 's/\//--/g')"
            SERVICE_HOME="/var/lib/llm-orchestrator"

            echo -e "\n=== Model Status ==="
            if sudo test -d "$CHAT_MODEL_DIR"; then
              SIZE=$(sudo du -sh "$CHAT_MODEL_DIR" | cut -f1)
              echo "[+] Chat Model Found: $CHAT_MODEL ($SIZE)"
            else
              echo "[-] Chat Model Missing: $CHAT_MODEL"
            fi

            if sudo test -d "$EMBED_MODEL_DIR"; then
              SIZE=$(sudo du -sh "$EMBED_MODEL_DIR" | cut -f1)
              echo "[+] Embed Model Found: $EMBED_MODEL ($SIZE)"
            else
              echo "[-] Embed Model Missing: $EMBED_MODEL"
            fi

            echo -e "\n=== Active Model ==="
            curl -s http://localhost:''${PORT:-8000}/health 2>/dev/null | jq . || echo "Service not responding"
          '';
        in
        {
          inherit
            serve-script
            service-download-script
            service-start-script
            service-stop-script
            service-restart-script
            service-status-script
            ;
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          packs = mkPackages system null;
        in
        {
          default = packs.serve-script;
          serve = packs.serve-script;
          service-download = packs.service-download-script;
          service-restart = packs.service-restart-script;
          service-start = packs.service-start-script;
          service-status = packs.service-status-script;
          service-stop = packs.service-stop-script;
        }
      );

      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.llm-orchestrator;
          llmPackages = mkPackages pkgs.stdenv.hostPlatform.system cfg;
        in
        with lib;
        {
          options.services.llm-orchestrator = {
            enable = mkEnableOption "vLLM Multi-Model Orchestrator";

            chatModel = mkOption {
              type = types.str;
              default = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit";
              description = "HuggingFace model ID for chat completions";
            };

            embedModel = mkOption {
              type = types.str;
              default = "Qwen/Qwen3-Embedding-0.6B";
              description = "HuggingFace model ID for embeddings";
            };

            port = mkOption {
              type = types.port;
              default = 8000;
              description = "Port to listen on";
            };

            host = mkOption {
              type = types.str;
              default = "0.0.0.0";
              description = "Host/IP to bind to";
            };

            gpuMemoryUtilization = mkOption {
              type = types.float;
              default = 0.85;
              description = "GPU memory fraction for chat model";
            };

            maxModelLen = mkOption {
              type = types.int;
              default = 32768;
              description = "Maximum context length for chat model";
            };

            maxNumSeqs = mkOption {
              type = types.int;
              default = 256;
              description = "Maximum concurrent sequences";
            };

            lmcache = {
              enable = mkEnableOption "LMCache KV offloading for chat model";

              maxCpuSize = mkOption {
                type = types.int;
                default = 64;
                description = "GB of CPU RAM for KV cache offloading";
              };

              chunkSize = mkOption {
                type = types.int;
                default = 256;
                description = "Token chunk size for LMCache";
              };
            };
          };

          config = mkIf cfg.enable {
            users.users.llm-orchestrator = {
              isSystemUser = true;
              group = "llm-orchestrator";
              description = "LLM Orchestrator Service User";
              home = "/var/lib/llm-orchestrator";
              createHome = true;
            };

            users.groups.llm-orchestrator = { };

            environment.systemPackages = [
              llmPackages.service-download-script
              llmPackages.service-start-script
              llmPackages.service-stop-script
              llmPackages.service-restart-script
              llmPackages.service-status-script
            ];

            systemd.services.llm-orchestrator = {
              description = "vLLM Multi-Model Orchestrator";
              after = [ "network-online.target" ];
              wants = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                User = "llm-orchestrator";
                Group = "llm-orchestrator";
                StateDirectory = "llm-orchestrator";
                WorkingDirectory = "/var/lib/llm-orchestrator";
                ExecStart = "${llmPackages.serve-script}/bin/serve";
                Restart = "always";
                RestartSec = "10s";
                NoNewPrivileges = true;
                PrivateTmp = true;
              };

              environment = {
                CHAT_MODEL = cfg.chatModel;
                EMBED_MODEL = cfg.embedModel;
                GPU_MEMORY_UTIL = toString cfg.gpuMemoryUtilization;
                HF_HOME = "/var/lib/llm-orchestrator/huggingface";
                HOST = cfg.host;
                MAX_MODEL_LEN = toString cfg.maxModelLen;
                MAX_NUM_SEQS = toString cfg.maxNumSeqs;
                PORT = toString cfg.port;
                TRITON_CACHE_DIR = "/var/lib/llm-orchestrator/vllm/triton";
                VLLM_CACHE_ROOT = "/var/lib/llm-orchestrator/vllm";
              }
              // lib.optionalAttrs cfg.lmcache.enable {
                LMCACHE_CHUNK_SIZE = toString cfg.lmcache.chunkSize;
                LMCACHE_LOCAL_CPU = "True";
                LMCACHE_MAX_LOCAL_CPU_SIZE = toString cfg.lmcache.maxCpuSize;
              };
            };
          };
        };
    };
}
