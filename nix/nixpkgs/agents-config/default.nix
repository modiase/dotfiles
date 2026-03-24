{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.agents-config;

  nvimMcpWrapper = pkgs.callPackage ../nvim-mcp-wrapper { };
  devlogsLib = pkgs.callPackage ../devlogs-lib { };

  conditionEvalScript = lib.concatStrings (
    lib.mapAttrsToList (name: expr: ''
      if ${expr}; then cond_args+=" --condition ${name}=true"; else cond_args+=" --condition ${name}=false"; fi
    '') cfg.conditions
  );

  extraDirArgs = lib.concatMapStrings (d: ''--extra-sections-dir "${d}"'') cfg.extraSectionsDirs;

  generateAgentsMd = pkgs.writeShellApplication {
    name = "generate-agents-md";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export PYTHONPATH="${devlogsLib.python}/lib:''${PYTHONPATH:-}"
      export DEVLOGS_COMPONENT="generate-agents-md"
      export AGENTS_SECTIONS_DIR="${./sections}"
      cond_args=""
      ${conditionEvalScript}
      # shellcheck disable=SC2086
      exec python3 ${./generate-agents-md.py} $cond_args ${extraDirArgs} "$@"
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
    conditions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        nix = "command -v nix >/dev/null 2>&1";
      };
      description = "Shell expressions evaluated at runtime to produce --condition flags. Each value should return 0 (true) or non-zero (false).";
    };
    extraSectionsDirs = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Additional directories containing .md section files with frontmatter";
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
    home.file.".agents/skills/build-image/SKILL.md".source = ./skills/build-image/SKILL.md;
    home.file.".agents/skills/cli-tools/SKILL.md".source = ./skills/cli-tools/SKILL.md;
    home.file.".agents/skills/commit-message/SKILL.md".source = ./skills/commit-message/SKILL.md;
    home.file.".agents/skills/devlogs/SKILL.md".source = ./skills/devlogs/SKILL.md;
  };
}
