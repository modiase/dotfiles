{
  pkgs,
  claudeCodePkg,
  configDir ? null,
}:
let
  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };

  getClaudeIdeEnv = pkgs.writeShellApplication {
    name = "get-claude-ide-env";
    runtimeInputs = [
      tmuxNvimSelect
      pkgs.jq
      pkgs.neovim-remote
    ];
    text = builtins.readFile ./scripts/get-claude-ide-env.sh;
  };

  generateAgentsMd = pkgs.writeShellApplication {
    name = "generate-agents-md";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export AGENTS_SECTIONS_DIR="${../agents-config/sections}"
      exec python3 ${../agents-config/generate-agents-md.py} "$@"
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
    _DL_WIN=""
    if [ -n "''${TMUX_PANE:-}" ]; then
        _DL_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
    fi
    _DL_TAG="claude"
    if [ -n "$_DL_WIN" ]; then _DL_TAG="claude(@$_DL_WIN)"; fi
    ide_env=$(get-claude-ide-env 2>/dev/null) || true
    if [ -n "$ide_env" ]; then
        eval "$ide_env"
        export CLAUDE_CODE_SSE_PORT ENABLE_IDE_INTEGRATION
        logger -t devlogs "[devlogs] INFO $_DL_TAG: IDE integration found port=$CLAUDE_CODE_SSE_PORT"
    else
        logger -t devlogs "[devlogs] INFO $_DL_TAG: no IDE integration"
    fi
    agents_md=$(generate-agents-md --agent claude)
    exec ${claudeCodePkg}/bin/claude --append-system-prompt "$agents_md" "$@"
  '';
}
