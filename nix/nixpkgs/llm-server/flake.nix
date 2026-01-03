{
  description = "vLLM server environment for Qwen3-Coder using nixpkgs vLLM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

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

          pythonEnv = pkgs.python312.withPackages (
            ps: with ps; [
              (pkgs.python312Packages.vllm.overridePythonAttrs (old: {
                postPatch = (old.postPatch or "") + ''
                  [ -f setup.py ] && sed -i 's/-j=[0-9]/-j=4/g' setup.py
                '';

                preBuild = (old.preBuild or "") + ''
                  export MAX_JOBS=4
                  export NIX_BUILD_CORES=4
                  export CMAKE_BUILD_PARALLEL_LEVEL=4
                '';
              }))
              huggingface-hub
              uvloop
            ]
          );

          cudaHome = pkgs.cudaPackages.cudatoolkit;
          nvcc = pkgs.cudaPackages.cuda_nvcc;
          gcc = pkgs.gcc;
          libPath = "${cudaHome}/lib:${pkgs.cudaPackages.cudnn}/lib";

          commonEnv = ''
            export CUDA_HOME=${cudaHome}
            export PATH="${nvcc}/bin:${gcc}/bin:''${PATH}"
            export LD_LIBRARY_PATH=${libPath}:''${LD_LIBRARY_PATH:-}
            export HF_HOME="''${HF_HOME:-$HOME/huggingface}"
            export VLLM_CACHE_ROOT="''${VLLM_CACHE_ROOT:-$HOME/vllm}"
            export TRITON_CACHE_DIR="''${VLLM_CACHE_ROOT}/triton"
            export MODEL="''${MODEL:-cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit}"
          '';

          serve-script = pkgs.writeShellScriptBin "serve" ''
            set -e
            ${commonEnv}
            mkdir -p "$HF_HOME" "$VLLM_CACHE_ROOT" "$TRITON_CACHE_DIR"

            exec ${pythonEnv}/bin/python -m vllm.entrypoints.openai.api_server \
                --model "$MODEL" \
                --max-model-len "''${MAX_MODEL_LEN:-30720}" \
                --gpu-memory-utilization "''${GPU_MEMORY_UTIL:-0.90}" \
                --max-num-seqs "''${MAX_NUM_SEQS:-256}" \
                --host "''${HOST:-0.0.0.0}" \
                --port "''${PORT:-8000}" \
                --trust-remote-code \
                --enable-auto-tool-choice \
                --tool-call-parser qwen3_coder
          '';

          service-download-script = pkgs.writeShellScriptBin "llm-server-download" ''
                        set -e
                        if [ "$EUID" -ne 0 ]; then
                           echo "Error: This script must be run as root (sudo) to write to the service directory."
                           exit 1
                        fi

                        SERVICE_USER="llm-server"
                        SERVICE_HOME="/var/lib/llm-server"

                        MODEL="''${MODEL:-cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit}"

                        echo "Downloading model '$MODEL' for user '$SERVICE_USER'..."

                        sudo -u "$SERVICE_USER" \
                          env \
                          HF_HOME="$SERVICE_HOME/huggingface" \
                          ${pythonEnv}/bin/hf download "$MODEL" --cache-dir "$SERVICE_HOME/huggingface"

                        echo "Download complete."

                        sudo -u "$SERVICE_USER" \
                           env \
                           HF_HOME="$SERVICE_HOME/huggingface" \
                           VLLM_CACHE_ROOT="$SERVICE_HOME/vllm" \
                           TRITON_CACHE_DIR="$SERVICE_HOME/vllm/triton" \
                           CUDA_HOME="${cudaHome}" \
                           PATH="${nvcc}/bin:${gcc}/bin:''${PATH}" \
                           LD_LIBRARY_PATH="${libPath}" \
                           GPU_MEMORY_UTIL=${
                             if cfg != null then toString cfg.gpuMemoryUtilization else "0.90"
                           } \
                           MAX_MODEL_LEN=${if cfg != null then toString cfg.maxModelLen else "30720"} \
                           MAX_NUM_SEQS=${if cfg != null then toString cfg.maxNumSeqs else "256"} \
                           ${pythonEnv}/bin/python -c "
            import os
            from vllm import LLM
            llm = LLM(
                model='$MODEL',
                max_model_len=${if cfg != null then toString cfg.maxModelLen else "30720"},
                gpu_memory_utilization=${if cfg != null then toString cfg.gpuMemoryUtilization else "0.90"},
                max_num_seqs=${if cfg != null then toString cfg.maxNumSeqs else "256"},
                trust_remote_code=True
            )
            "

                        echo "Warmup complete. You can now start the service with: llm-server-start"
          '';

          service-start-script = pkgs.writeShellScriptBin "llm-server-start" ''
            set -e
            echo "Enabling and starting llm-server..."
            sudo systemctl reset-failed llm-server
            sudo systemctl enable --now llm-server
            sudo systemctl status llm-server --no-pager
          '';

          service-stop-script = pkgs.writeShellScriptBin "llm-server-stop" ''
            set -e
            echo "Stopping and disabling llm-server..."
            sudo systemctl disable --now llm-server
            sudo systemctl status llm-server --no-pager || true
          '';

          service-restart-script = pkgs.writeShellScriptBin "llm-server-restart" ''
            set -e
            echo "Restarting llm-server..."
            sudo systemctl reset-failed llm-server
            sudo systemctl restart llm-server
            sudo systemctl status llm-server --no-pager
          '';

          service-clean-kernels-script = pkgs.writeShellScriptBin "llm-server-clean-kernels" ''
            set -e
            echo "WARNING: This will delete all compiled kernels and vLLM cache."
            echo "The next start will require a long compilation time."
            read -p "Are you sure? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Cleaning /var/lib/llm-server/vllm..."
                sudo rm -rf /var/lib/llm-server/vllm
                echo "Done."
            else
                echo "Cancelled."
            fi
          '';

          service-clean-models-script = pkgs.writeShellScriptBin "llm-server-clean-models" ''
            set -e
            echo "WARNING: This will delete all downloaded models in /var/lib/llm-server/huggingface."
            read -p "Are you sure? (y/N) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "Cleaning /var/lib/llm-server/huggingface..."
                sudo rm -rf /var/lib/llm-server/huggingface
                echo "Done."
            else
                echo "Cancelled."
            fi
          '';

          service-status-script = pkgs.writeShellScriptBin "llm-server-status" ''
            set -e
            echo "=== Service Status ==="
            systemctl status llm-server --no-pager || echo "Stopped (or not loaded)"

            SERVICE_HOME="/var/lib/llm-server"
            MODEL="''${MODEL:-cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit}"

            MODEL_DIR="$SERVICE_HOME/huggingface/models--$(echo $MODEL | sed 's/\//--/g')"
            TRITON_DIR="$SERVICE_HOME/vllm/triton"

            echo -e "\n=== Storage Status ==="
            if sudo test -d "$MODEL_DIR"; then
              SIZE=$(sudo du -sh "$MODEL_DIR" | cut -f1)
              echo "[+] Model Found: $MODEL ($SIZE)"
            else
              echo "[-] Model Missing: $MODEL (Expected at: $MODEL_DIR)"
            fi

            if sudo test -d "$TRITON_DIR"; then
               echo "[+] Triton Cache Found (Kernels likely compiled)"
            else
               echo "[-] Triton Cache Missing (Kernels will compile on next start)"
            fi
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
            service-clean-kernels-script
            service-clean-models-script
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
          serve = packs.serve-script;
          service-download = packs.service-download-script;
          service-start = packs.service-start-script;
          service-stop = packs.service-stop-script;
          service-restart = packs.service-restart-script;
          service-status = packs.service-status-script;
          service-clean-kernels = packs.service-clean-kernels-script;
          service-clean-models = packs.service-clean-models-script;
          default = packs.serve-script;
        }
      );

      apps = forAllSystems (
        system:
        let
          packs = mkPackages system null;
        in
        {
          serve = {
            type = "app";
            program = "${packs.serve-script}/bin/serve";
          };
          service-download = {
            type = "app";
            program = "${packs.service-download-script}/bin/llm-server-download";
          };
          service-start = {
            type = "app";
            program = "${packs.service-start-script}/bin/llm-server-start";
          };
          service-stop = {
            type = "app";
            program = "${packs.service-stop-script}/bin/llm-server-stop";
          };
          service-restart = {
            type = "app";
            program = "${packs.service-restart-script}/bin/llm-server-restart";
          };
          service-status = {
            type = "app";
            program = "${packs.service-status-script}/bin/llm-server-status";
          };
          service-clean-kernels = {
            type = "app";
            program = "${packs.service-clean-kernels-script}/bin/llm-server-clean-kernels";
          };
          service-clean-models = {
            type = "app";
            program = "${packs.service-clean-models-script}/bin/llm-server-clean-models";
          };
          default = {
            type = "app";
            program = "${packs.serve-script}/bin/serve";
          };
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
          cfg = config.services.llm-server;
          llmPackages = mkPackages pkgs.stdenv.hostPlatform.system cfg;
        in
        with lib;
        {
          options.services.llm-server = {
            enable = mkEnableOption "vLLM Inference Server";

            model = mkOption {
              type = types.str;
              default = "cpatonn/Qwen3-Coder-30B-A3B-Instruct-AWQ-4bit";
              description = "HuggingFace model ID to serve";
            };

            port = mkOption {
              type = types.port;
              default = 8000;
              description = "Port to listen on";
            };

            gpuMemoryUtilization = mkOption {
              type = types.float;
              default = 0.90;
              description = "Fraction of GPU memory to use";
            };

            maxModelLen = mkOption {
              type = types.int;
              default = 30720;
              description = "Maximum model length";
            };

            maxNumSeqs = mkOption {
              type = types.int;
              default = 256;
              description = "Maximum number of sequences per iteration";
            };
          };

          config = mkIf cfg.enable {
            users.users.llm-server = {
              isSystemUser = true;
              group = "llm-server";
              description = "vLLM Service User";
              home = "/var/lib/llm-server";
              createHome = true;
            };

            users.groups.llm-server = { };

            environment.systemPackages = [
              llmPackages.service-download-script
              llmPackages.service-start-script
              llmPackages.service-stop-script
              llmPackages.service-restart-script
              llmPackages.service-status-script
              llmPackages.service-clean-kernels-script
              llmPackages.service-clean-models-script
            ];

            systemd.services.llm-server = {
              description = "vLLM Inference Server";
              after = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                User = "llm-server";
                Group = "llm-server";
                StateDirectory = "llm-server";
                WorkingDirectory = "/var/lib/llm-server";
                ExecStart = "${llmPackages.serve-script}/bin/serve";
                Restart = "always";
                RestartSec = "10s";

                NoNewPrivileges = true;
                PrivateTmp = true;
              };

              environment = {
                HOST = "0.0.0.0";
                PORT = toString cfg.port;
                MODEL = cfg.model;
                GPU_MEMORY_UTIL = toString cfg.gpuMemoryUtilization;
                MAX_MODEL_LEN = toString cfg.maxModelLen;
                MAX_NUM_SEQS = toString cfg.maxNumSeqs;
                HF_HOME = "/var/lib/llm-server/huggingface";
                VLLM_CACHE_ROOT = "/var/lib/llm-server/vllm";
                TRITON_CACHE_DIR = "/var/lib/llm-server/vllm/triton";
              };
            };
          };
        };
    };
}
