{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.opencode;
  agentsCfg = config.dotfiles.agents-config;

  homeDir = config.home.homeDirectory;

  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
  nvr = pkgs.callPackage ../nvr { };
  ding = pkgs.callPackage ../ding { };

  planReviewPlugin = pkgs.replaceVars ./plugins/plan-review.ts {
    tmuxNvimSelect = "${tmuxNvimSelect}/bin/tmux-nvim-select";
    nvr = "${nvr}/bin/nvr";
  };

  notifyPlugin = pkgs.replaceVars ./plugins/notify.ts {
    ding = "${ding}/bin/ding";
  };

  explorePrompt = ''
    You are a fast, read-only codebase exploration agent. FOLLOW WITHOUT EXCEPTION:

    1. Answer ONLY the question asked — no preamble, no summary, no suggestions
    2. Output structured bullets, never prose paragraphs
    3. Cite every claim as file:line (e.g. src/main.ts:42)
    4. Stop immediately when the question is answered — do not explore further
    5. If the answer is not found, say so in one line

    Output format:
    - **Finding**: description (file:line)
    - **Finding**: description (file:line)
  '';

  researchPrompt = ''
    You are a research-only agent. You may read code, search the codebase, and browse the web, but you MUST NOT modify any files.

    Methodology:
    1. Clarify the question — restate what you're investigating
    2. Hypothesise — list candidate explanations or locations
    3. Gather evidence — use read/grep/glob/bash (read-only commands only) to verify
    4. Cross-reference — check multiple sources before concluding
    5. Report — present findings with file:line citations, distinguishing facts from interpretation

    Bash is available but restricted to read-only commands. FORBIDDEN in bash: rm, mv, cp, mkdir, touch, chmod, chown, sed, awk (with -i), tee, write, append (>), edit, git commit, git push, git checkout, git reset, git rebase, kill, pkill.
  '';

  baseMcp = lib.mapAttrs (_name: server: {
    type = "local";
    command = [ server.command ] ++ server.args;
    environment = server.env;
    enabled = true;
  }) agentsCfg.mcpServers;

  exaMcpWrapper = pkgs.writeShellApplication {
    name = "opencode-exa-mcp";
    runtimeInputs = [ pkgs.pnpm ];
    text = builtins.readFile ./exa-mcp-wrapper.sh;
  };

  darwinMcp = lib.optionalAttrs pkgs.stdenv.isDarwin {
    exa = {
      type = "local";
      command = [ "opencode-exa-mcp" ];
      enabled = true;
    };
  };

  mcp = baseMcp // darwinMcp;

  opencodeConfig = pkgs.writeText "opencode.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      autoupdate = false;
      plugin = [
        "${homeDir}/.config/opencode/plugins/plan-review.ts"
        "${homeDir}/.config/opencode/plugins/notify.ts"
      ];
      agent = {
        plan.prompt = "Before writing a plan, call @explore with a carefully constructed prompt to gather the codebase context you need — relevant files, structure, dependencies, and existing patterns. Use the explore findings to ground your plan in reality rather than assumptions. You may also use the question tool to ask the user clarifying questions. Once your plan is ready, you MUST call the submit_plan tool — do NOT present the plan in chat. Format every actionable item as a markdown checkbox (- [ ] item). If the user rejects, revise based on their feedback and call submit_plan again. NEVER proceed to implementation without plan approval via submit_plan.";

        explore = {
          model = "openrouter/google/gemini-2.5-flash";
          description = "Fast read-only codebase exploration via @explore";
          mode = "subagent";
          hidden = false;
          color = "#4ade80";
          steps = 30;
          prompt = explorePrompt;
          permission = {
            read = "allow";
            glob = "allow";
            grep = "allow";
            list = "allow";
            codesearch = "allow";
            lsp = "allow";
            todoread = "allow";
            question = "allow";
            bash = "deny";
            edit = "deny";
            webfetch = "deny";
            websearch = "deny";
            todowrite = "deny";
            task = "deny";
            skill = "deny";
            external_directory = "deny";
            doom_loop = "deny";
          };
        };

        research = {
          description = "Research-only: investigate code, docs, web — no modifications";
          mode = "primary";
          color = "#60a5fa";
          steps = 50;
          prompt = researchPrompt;
          permission = {
            read = "allow";
            glob = "allow";
            grep = "allow";
            list = "allow";
            bash = "allow";
            codesearch = "allow";
            lsp = "allow";
            webfetch = "allow";
            websearch = "allow";
            question = "allow";
            todoread = "allow";
            task = "allow";
            edit = "deny";
            todowrite = "deny";
            skill = "deny";
            external_directory = "deny";
            doom_loop = "deny";
          };
        };
      };
      inherit mcp;
    }
  );

  tuiConfig = pkgs.writeText "opencode-tui.json" (builtins.readFile ./config/tui.json);

  agentsDir = "$HOME/.agents";
in
{
  options.dotfiles.opencode = {
    enable = lib.mkEnableOption "opencode with extensions";
  };

  config = lib.mkIf cfg.enable {
    home = {
      packages = [ pkgs.opencode ] ++ lib.optionals pkgs.stdenv.isDarwin [ exaMcpWrapper ];

      file.".config/opencode/opencode.json".source = opencodeConfig;
      file.".config/opencode/tui.json".source = tuiConfig;

      activation = {
        opencode-agent-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ln -sfn "${agentsDir}/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
          $DRY_RUN_CMD ln -sfn "${agentsDir}/skills" "$HOME/.config/opencode/skills"
        '';
        opencode-plugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p "$HOME/.config/opencode/plugins"
          $DRY_RUN_CMD cp -f ${planReviewPlugin} "$HOME/.config/opencode/plugins/plan-review.ts"
          $DRY_RUN_CMD cp -f ${notifyPlugin} "$HOME/.config/opencode/plugins/notify.ts"
          $DRY_RUN_CMD cp -f ${../devlogs-lib/devlogs.ts} "$HOME/.config/opencode/plugins/devlogs.ts"
        '';
      };
    };
  };
}
