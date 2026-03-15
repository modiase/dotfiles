{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.gemini-cli;
  generateAgentsMd = config.dotfiles.agents-config.generateAgentsMd;

  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  ding = pkgs.callPackage ../ding { };
  nvr = pkgs.callPackage ../nvr { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  hookScript = pkgs.writeShellApplication {
    name = "gemini-hook";
    runtimeInputs = [
      ding
      generateAgentsMd
      pkgs.jq
    ];
    text = ''
      export DEVLOGS_COMPONENT="gemini-hook"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/hook.sh}
    '';
  };

  hookBin = "${hookScript}/bin/gemini-hook";

  agentsCfg = config.dotfiles.agents-config;

  baseSettings = import ./settings.nix { inherit hookBin; };
  settings = baseSettings // {
    mcpServers = agentsCfg.mcpServers;
  };
  settingsJson = pkgs.writeText "gemini-settings.json" (builtins.toJSON settings);

  policyRules = import ./policies.nix;
  tomlFormat = pkgs.formats.toml { };
  policyFile = tomlFormat.generate "managed.toml" { rule = policyRules; };

  geminiEditor = pkgs.writeShellApplication {
    name = "gemini-editor";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.gum
      nvr
      pkgs.tmux
    ];
    text = ''
      export DEVLOGS_COMPONENT="gemini-editor"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/gemini-editor.sh}
    '';
  };

  getGeminiIdeEnv = pkgs.writeShellApplication {
    name = "get-gemini-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.lsof
    ];
    text = ''
      export DEVLOGS_COMPONENT="get-gemini-ide-env"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
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
      export EDITOR=gemini-editor
      export DEVLOGS_COMPONENT="gemini"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ide_env=$(get-gemini-ide-env 2>/dev/null) || true
      if [ -n "$ide_env" ]; then
          eval "$ide_env"
          clog info "IDE integration found port=$GEMINI_CLI_IDE_SERVER_PORT"
          gemini-nvim-ide-bridge -socket "$NVIM_LISTEN_ADDRESS" -port "$GEMINI_CLI_IDE_SERVER_PORT" -ide-pids "$IDE_PIDS" -workspace "$(pwd)" 2>&1 | logger -t devlogs &
      else
          clog info "no IDE integration"
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

      activation.gemini-settings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.gemini"
        $DRY_RUN_CMD cp -f "${settingsJson}" "$HOME/.gemini/settings.json"
        $DRY_RUN_CMD chmod u+w "$HOME/.gemini/settings.json"
      '';

    };
  };
}
