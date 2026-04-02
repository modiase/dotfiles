{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.gemini-cli;
  inherit (config.dotfiles.agents-config) generateAgentsMd;

  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  ding = pkgs.callPackage ../ding { };
  nvr = pkgs.callPackage ../nvr { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  planResponder = pkgs.callPackage ../agents-plan-responder { };

  planScriptInputs =
    with pkgs;
    [
      jq
      tmux
      util-linux
    ]
    ++ [
      nvr
      planResponder
      tmuxNvimSelect
    ];

  openPlanScript = pkgs.writeShellApplication {
    name = "gemini-nvim-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init gemini-nvim-plan
      ${builtins.readFile ./scripts/nvim-plan.sh}
    '';
  };

  closePlanScript = pkgs.writeShellApplication {
    name = "gemini-close-plan";
    runtimeInputs = planScriptInputs;
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init gemini-close-plan
      ${builtins.readFile ./scripts/close-plan.sh}
    '';
  };

  hookScript = pkgs.writeShellApplication {
    name = "gemini-hook";
    runtimeInputs = [
      ding
      generateAgentsMd
      pkgs.jq
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init gemini-hook
      ${builtins.readFile ./scripts/hook.sh}
    '';
  };

  formatHookScript = pkgs.callPackage ../format-hook { name = "gemini-format-hook"; };

  hookBin = "${hookScript}/bin/gemini-hook";
  openPlanBin = "${openPlanScript}/bin/gemini-nvim-plan";
  closePlanBin = "${closePlanScript}/bin/gemini-close-plan";
  formatHookBin = "${formatHookScript}/bin/gemini-format-hook";

  agentsCfg = config.dotfiles.agents-config;

  baseSettings = import ./settings.nix {
    inherit
      hookBin
      openPlanBin
      closePlanBin
      formatHookBin
      ;
  };
  settings = baseSettings // {
    inherit (agentsCfg) mcpServers;
  };
  settingsJson = pkgs.writeText "gemini-settings.json" (builtins.toJSON settings);

  policyRules = import ./policies.nix;
  tomlFormat = pkgs.formats.toml { };
  policyFile = tomlFormat.generate "managed.toml" { rule = policyRules; };

  geminiEditor = pkgs.writeShellApplication {
    name = "gemini-editor";
    runtimeInputs = [
      (pkgs.callPackage ./scripts/gemini-editor { })
      tmuxNvimSelect
      pkgs.tmux
      pkgs.neovim
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init gemini-editor
      exec gemini-editor-go "$@"
    '';
  };

  getGeminiIdeEnv = pkgs.writeShellApplication {
    name = "get-gemini-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.lsof
    ];
    text = ''
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init get-gemini-ide-env
      ${builtins.readFile ./scripts/get-gemini-ide-env.sh}
    '';
  };

  wrappedGemini = pkgs.writeShellApplication {
    name = "gemini";
    runtimeInputs = [
      geminiEditor
      getGeminiIdeEnv
      pkgs.gemini-nvim-ide-bridge
      pkgs.inetutils
    ];
    text = ''
      export WRAPPER_ID
      WRAPPER_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
      export EDITOR=gemini-editor
      export GEMINI_SYSTEM_MD="$HOME/.gemini/system.md"
      export DEVLOGS_INSTANCE="$WRAPPER_ID"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      devlogs_init gemini
      ide_env=$(get-gemini-ide-env 2>/dev/null) || true
      if [ -n "$ide_env" ]; then
          eval "$ide_env"
          clog info "IDE integration found port=$GEMINI_CLI_IDE_SERVER_PORT socket=$NVIM_LISTEN_ADDRESS"
          gemini-nvim-ide-bridge -socket "$NVIM_LISTEN_ADDRESS" -port "$GEMINI_CLI_IDE_SERVER_PORT" -ide-pids "$IDE_PIDS" -workspace "$(pwd)" -wrapper-id "$WRAPPER_ID" &
      else
          clog info "IDE integration (no initial nvim)"
          IDE_PORT=$((RANDOM % 16384 + 49152))
          all_pids="$$"
          current_pid=$$
          for _ in {1..5}; do
              parent_pid=$(ps -o ppid= -p "$current_pid" 2>/dev/null | tr -d ' ') || true
              if [[ -n "$parent_pid" && "$parent_pid" -gt 1 ]]; then
                  all_pids="$all_pids $parent_pid"
                  current_pid=$parent_pid
              else
                  break
              fi
          done
          export GEMINI_CLI_IDE_SERVER_PORT="$IDE_PORT"
          export ENABLE_IDE_INTEGRATION=true
          gemini-nvim-ide-bridge -port "$IDE_PORT" -ide-pids "$all_pids" -workspace "$(pwd)" -wrapper-id "$WRAPPER_ID" &
      fi
      exec ${cfg.executable} "$@"
    '';
  };
in
{
  options.dotfiles.gemini-cli = {
    enable = lib.mkEnableOption "Gemini CLI with extensions";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.gemini-cli;
      description = "Gemini CLI package. Set null to skip installation.";
    };
    executable = lib.mkOption {
      type = lib.types.str;
      default = if cfg.package != null then "''${cfg.package}/bin/gemini" else "gemini";
      description = "Command or path to the Gemini executable. Defaults to the package binary or 'gemini' in PATH.";
    };
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [
        wrappedGemini
      ];

      file.".gemini/policies/managed.toml".source = policyFile;
      file.".gemini/system.md".source = ./system.md;

      activation.gemini-settings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.gemini"
        settings="$HOME/.gemini/settings.json"
        if [ -f "$settings" ]; then
          $DRY_RUN_CMD ${pkgs.jq}/bin/jq -s '
            .[1] * {security: {auth: (.[0].security.auth // {})}}
          ' "$settings" "${settingsJson}" > "$settings.tmp"
          $DRY_RUN_CMD mv "$settings.tmp" "$settings"
        else
          $DRY_RUN_CMD cp "${settingsJson}" "$settings"
        fi
        $DRY_RUN_CMD chmod u+w "$settings"
      '';

    };
  };
}
