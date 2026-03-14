{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.agents-config;

  nvimMcpWrapper = pkgs.callPackage ../nvim-mcp-wrapper { };

  generateAgentsMd = pkgs.writeShellApplication {
    name = "generate-agents-md";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export AGENTS_SECTIONS_DIR="${./sections}"
      exec python3 ${./generate-agents-md.py} "$@"
    '';
  };
in
{
  options.dotfiles.agents-config = {
    enable = lib.mkEnableOption "Cross-agent configuration (dynamic AGENTS.md and skills)";
    generateAgentsMd = lib.mkOption {
      type = lib.types.package;
      default = generateAgentsMd;
      readOnly = true;
      description = "The generate-agents-md package, for use by agent modules";
    };
    mcpServers = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      description = "Shared MCP server definitions propagated to all agents";
    };
  };

  config = lib.mkIf cfg.enable {
    dotfiles.agents-config.mcpServers.nvim = {
      type = "stdio";
      command = "nvim-mcp";
      args = [ ];
      env = { };
    };

    home.packages = [ nvimMcpWrapper ];

    home.file.".agents/skills/adding-skills/SKILL.md".source = ./skills/adding-skills/SKILL.md;
    home.file.".agents/skills/cli-tools/SKILL.md".source = ./skills/cli-tools/SKILL.md;
    home.file.".agents/skills/commit-message/SKILL.md".source = ./skills/commit-message/SKILL.md;
    home.file.".agents/skills/devlogs/SKILL.md".source = ./skills/devlogs/SKILL.md;
  };
}
