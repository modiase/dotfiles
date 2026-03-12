{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.gemini-cli;
  generateAgentsMd = config.dotfiles.agents-config.generateAgentsMd;

  ding = pkgs.callPackage ../ding { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  hookScript = pkgs.writeShellApplication {
    name = "gemini-hook";
    runtimeInputs = [
      ding
      generateAgentsMd
      pkgs.jq
    ];
    text = builtins.readFile ./scripts/hook.sh;
  };

  hookBin = "${hookScript}/bin/gemini-hook";

  settings = import ./settings.nix { inherit hookBin; };
  settingsJson = pkgs.writeText "gemini-settings.json" (builtins.toJSON settings);

  mcpSettings = {
    mcpServers = {
      nvim = {
        type = "stdio";
        command = "nvim-mcp";
        args = [ ];
        env = { };
      };
    };
  };
  mcpJson = pkgs.writeText "mcp.json" (builtins.toJSON mcpSettings);

  policyRules = import ./policies.nix;
  tomlFormat = pkgs.formats.toml { };
  policyFile = tomlFormat.generate "managed.toml" { rule = policyRules; };

  geminiEditor = pkgs.writeShellApplication {
    name = "gemini-editor";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.gum
      pkgs.neovim-remote
      pkgs.tmux
    ];
    text = builtins.readFile ./scripts/gemini-editor.sh;
  };

  getGeminiIdeEnv = pkgs.writeShellApplication {
    name = "get-gemini-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.lsof
    ];
    text = builtins.readFile ./scripts/get-gemini-ide-env.sh;
  };

  nvimMcpWrapper = pkgs.callPackage ../nvim-mcp-wrapper { };

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
      _DL_WIN=""
      if [ -n "''${TMUX_PANE:-}" ]; then
          _DL_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
      fi
      _DL_TAG="gemini"
      if [ -n "$_DL_WIN" ]; then _DL_TAG="gemini(@$_DL_WIN)"; fi
      ide_env=$(get-gemini-ide-env 2>/dev/null) || true
      if [ -n "$ide_env" ]; then
          eval "$ide_env"
          logger -t devlogs "[devlogs] INFO $_DL_TAG: IDE integration found port=$GEMINI_CLI_IDE_SERVER_PORT"
          gemini-nvim-ide-bridge -socket "$NVIM_LISTEN_ADDRESS" -port "$GEMINI_CLI_IDE_SERVER_PORT" -ide-pids "$IDE_PIDS" -workspace "$(pwd)" 2>&1 | logger -t devlogs &
      else
          logger -t devlogs "[devlogs] INFO $_DL_TAG: no IDE integration"
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
        nvimMcpWrapper
      ];

      file.".gemini/policies/managed.toml".source = policyFile;

      activation.gemini-settings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD mkdir -p "$HOME/.gemini"
        $DRY_RUN_CMD cp -f "${settingsJson}" "$HOME/.gemini/settings.json"
        $DRY_RUN_CMD chmod u+w "$HOME/.gemini/settings.json"
      '';

      activation.gemini-mcp-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD cp -f "${mcpJson}" "$HOME/.mcp.json"
        $DRY_RUN_CMD chmod u+w "$HOME/.mcp.json"
      '';
    };
  };
}
