{
  pkgs,
  claudeCodePkg,
  generateAgentsMd,
  configDir ? null,
}:
let
  devlogsLib = pkgs.callPackage ../devlogs-lib { };
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  getClaudeIdeEnv = pkgs.writeShellApplication {
    name = "get-claude-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.jq
      pkgs.neovim-remote
    ];
    text = ''
      export DEVLOGS_COMPONENT="get-claude-ide-env"
      # shellcheck source=/dev/null
      source ${devlogsLib.shell}/lib/devlogs.sh
      ${builtins.readFile ./scripts/get-claude-ide-env.sh}
    '';
  };

  configDirExport = if configDir != null then ''export CLAUDE_CONFIG_DIR="${configDir}"'' else "";
in
pkgs.writeShellApplication {
  name = "claude";
  runtimeInputs = [
    getClaudeIdeEnv
    generateAgentsMd
  ];
  text = ''
    ${configDirExport}
    export DEVLOGS_COMPONENT="claude"
    # shellcheck source=/dev/null
    source ${devlogsLib.shell}/lib/devlogs.sh
    ide_env=$(get-claude-ide-env 2>/dev/null) || true
    if [ -n "$ide_env" ]; then
        eval "$ide_env"
        export CLAUDE_CODE_SSE_PORT ENABLE_IDE_INTEGRATION
        clog info "IDE integration found port=$CLAUDE_CODE_SSE_PORT"
    else
        clog info "no IDE integration"
    fi
    agents_md=$(generate-agents-md --agent claude)
    exec ${claudeCodePkg}/bin/claude --append-system-prompt "$agents_md" "$@"
  '';
}
