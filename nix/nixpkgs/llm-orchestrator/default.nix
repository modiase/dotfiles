{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkPythonEnv =
    pkgs:
    pkgs.python312.withPackages (
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
        huggingface-hub
      ]
    );

  cfg = config.services.vllm;
  pythonEnv = mkPythonEnv pkgs;
  cudaHome = pkgs.cudaPackages.cudatoolkit;
  libPath = "${cudaHome}/lib:${pkgs.cudaPackages.cudnn}/lib";
  nvcc = pkgs.cudaPackages.cuda_nvcc;

  instanceModule =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkEnableOption "vLLM instance ${name}";

        model = lib.mkOption {
          type = lib.types.str;
          description = "HuggingFace model ID";
        };

        port = lib.mkOption {
          type = lib.types.port;
          description = "Port to listen on";
        };

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Host/IP to bind to";
        };

        gpuMemoryUtilization = lib.mkOption {
          type = lib.types.float;
          default = 0.80;
          description = "GPU memory fraction";
        };

        maxModelLen = lib.mkOption {
          type = lib.types.int;
          default = 32768;
          description = "Maximum context length";
        };

        maxNumSeqs = lib.mkOption {
          type = lib.types.int;
          default = 64;
          description = "Maximum concurrent sequences";
        };

        task = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Task type (e.g., 'embed' for embedding models)";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Extra arguments to pass to vllm serve";
        };
      };
    };

  mkService = name: icfg: {
    description = "vLLM Server (${name})";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [
      nvcc
      pkgs.gcc
    ];

    serviceConfig = {
      User = "vllm";
      Group = "vllm";
      StateDirectory = "vllm";
      WorkingDirectory = "/var/lib/vllm";
      Restart = "always";
      RestartSec = "10s";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ExecStart =
        let
          args = [
            "${pythonEnv}/bin/vllm"
            "serve"
            icfg.model
            "--host"
            icfg.host
            "--port"
            (toString icfg.port)
            "--gpu-memory-utilization"
            (toString icfg.gpuMemoryUtilization)
            "--max-model-len"
            (toString icfg.maxModelLen)
            "--max-num-seqs"
            (toString icfg.maxNumSeqs)
            "--enable-sleep-mode"
            "--enforce-eager"
            "--trust-remote-code"
            "--enable-prefix-caching"
          ]
          ++ lib.optionals (icfg.task != null) [
            "--task"
            icfg.task
          ]
          ++ icfg.extraArgs;
        in
        lib.concatStringsSep " " args;
    };

    environment = {
      CUDA_HOME = "${cudaHome}";
      HF_HOME = "/var/lib/vllm/huggingface";
      LD_LIBRARY_PATH = libPath;
      TRITON_CACHE_DIR = "/var/lib/vllm/triton";
      VLLM_CACHE_ROOT = "/var/lib/vllm/cache";
    };
  };

  enabledInstances = lib.filterAttrs (_: icfg: icfg.enable) cfg.instances;
in
{
  options.services.vllm = {
    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = { };
      description = "vLLM server instances";
    };
  };

  config = lib.mkIf (enabledInstances != { }) {
    users.users.vllm = {
      isSystemUser = true;
      group = "vllm";
      description = "vLLM Service User";
      home = "/var/lib/vllm";
      createHome = true;
    };

    users.groups.vllm = { };

    systemd.services = lib.mapAttrs' (
      name: icfg: lib.nameValuePair "vllm-${name}" (mkService name icfg)
    ) enabledInstances;
  };
}
