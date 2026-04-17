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
  colors = import ../../colors.nix;

  tmuxNvimSelect = pkgs.callPackage ../tmux-nvim { };
  nvr = pkgs.callPackage ../nvr { };
  attn = pkgs.callPackage ../attn { };

  planReviewPlugin = pkgs.replaceVars ./plugins/plan-review.ts {
    tmuxNvimSelect = "${tmuxNvimSelect}/bin/tmux-nvim-select";
    nvr = "${nvr}/bin/nvr";
  };

  notifyPlugin = pkgs.replaceVars ./plugins/notify.ts {
    attn = "${attn}/bin/attn";
  };

  contextReinjectPlugin = ./plugins/context-reinject.ts;
  tokenCounterPlugin = ./plugins/token-counter.tsx;

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

    NEVER:
    - Guess or infer file contents — always verify with read/grep before citing
    - Explore beyond the scope of the question
    - Return prose paragraphs — use structured bullets only
    - Suggest code changes or improvements — you are read-only
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

  # Baked theme that mirrors the terminal palette from colors.nix. Avoids the
  # OSC 4/10/11 query race opencode hits on first launch inside tmux, which
  # otherwise falls back to the built-in `opencode` theme (bg #0a0a0a) and
  # clashes with our actual terminal bg. See sst/opencode#19254.
  pastelGrayTheme = pkgs.writeText "opencode-pastel-gray-theme.json" (
    let
      h = c: "#${c}";
    in
    builtins.toJSON {
      "$schema" = "https://opencode.ai/theme.json";
      defs = {
        bg = h colors.base16.base00;
        bgPanel = h colors.base16.base01;
        bgElement = h colors.base16.base02;
        border = h colors.base16.base02;
        borderSubtle = h colors.base16.base01;
        fg = h colors.base16.base05;
        fgMuted = h colors.foregroundMuted;
        fgDim = h colors.base16.base03;
        red = h colors.base16.base08;
        green = h colors.base16.base09;
        yellow = h colors.base16.base0B;
        blue = h colors.base16.base0D;
        magenta = h colors.base16.base0E;
        cyan = h colors.base16.base0C;
        pink = h colors.base16.base0A;
        diffAddBg = h colors.diffAdd;
        diffRemoveBg = h colors.diffDelete;
      };
      theme = {
        primary = "blue";
        secondary = "magenta";
        accent = "cyan";
        background = "bg";
        backgroundPanel = "bgPanel";
        backgroundElement = "bgElement";
        border = "border";
        borderActive = "blue";
        borderSubtle = "borderSubtle";
        error = "red";
        warning = "yellow";
        success = "green";
        info = "blue";
        text = "fg";
        textMuted = "fgDim";
        diffAdded = "green";
        diffRemoved = "red";
        diffContext = "fgDim";
        diffHunkHeader = "blue";
        diffHighlightAdded = "green";
        diffHighlightRemoved = "red";
        diffAddedBg = "diffAddBg";
        diffRemovedBg = "diffRemoveBg";
        diffContextBg = "bg";
        diffLineNumber = "fgDim";
        diffAddedLineNumberBg = "diffAddBg";
        diffRemovedLineNumberBg = "diffRemoveBg";
        markdownText = "fg";
        markdownHeading = "blue";
        markdownLink = "cyan";
        markdownLinkText = "fg";
        markdownCode = "green";
        markdownBlockQuote = "fgMuted";
        markdownEmph = "magenta";
        markdownStrong = "pink";
        markdownHorizontalRule = "fgDim";
        markdownListItem = "fg";
        markdownListEnumeration = "blue";
        markdownImage = "cyan";
        markdownImageText = "fg";
        markdownCodeBlock = "green";
        syntaxComment = "fgDim";
        syntaxKeyword = "magenta";
        syntaxFunction = "blue";
        syntaxVariable = "red";
        syntaxString = "yellow";
        syntaxNumber = "green";
        syntaxType = "pink";
        syntaxOperator = "cyan";
        syntaxPunctuation = "fg";
      };
    }
  );

  opencodeConfig = pkgs.writeText "opencode.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      autoupdate = false;
      plugin = [
        "${homeDir}/.config/opencode/plugins/plan-review.ts"
        "${homeDir}/.config/opencode/plugins/notify.ts"
        "${homeDir}/.config/opencode/plugins/context-reinject.ts"
      ];
      agent = {
        plan.prompt = builtins.concatStringsSep " " [
          "Before writing a plan, you MUST call @explore at least once. Your explore prompt must ask for:"
          "1) Existing implementations of similar functionality,"
          "2) File structure and naming conventions in the affected area,"
          "3) Dependencies and imports that will be affected."
          "Use the explore findings to ground your plan in reality rather than assumptions."
          "You may also use the question tool to ask the user clarifying questions."
          "After receiving explore results, your plan MUST:"
          "reference specific files and line numbers from explore findings,"
          "reuse existing functions/utilities identified by explore,"
          "and note any conventions that must be followed."
          "Once your plan is ready, you MUST call the submit_plan tool — do NOT present the plan in chat."
          "Format every actionable item as a markdown checkbox (- [ ] item)."
          "If the user rejects, revise based on their feedback and call submit_plan again."
          "NEVER proceed to implementation without plan approval via submit_plan."
        ];

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

  tuiConfig = pkgs.writeText "opencode-tui.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/tui.json";
      theme = "pastel-gray";
      plugin = [
        "${homeDir}/.config/opencode/plugins/token-counter.tsx"
      ];
    }
  );

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
      file.".config/opencode/themes/pastel-gray.json".source = pastelGrayTheme;

      activation = {
        opencode-agent-links = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD ln -sfn "${agentsDir}/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
          $DRY_RUN_CMD ln -sfn "${agentsDir}/skills" "$HOME/.config/opencode/skills"
        '';
        opencode-plugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p "$HOME/.config/opencode/plugins"
          $DRY_RUN_CMD cp -f ${planReviewPlugin} "$HOME/.config/opencode/plugins/plan-review.ts"
          $DRY_RUN_CMD cp -f ${notifyPlugin} "$HOME/.config/opencode/plugins/notify.ts"
          $DRY_RUN_CMD cp -f ${contextReinjectPlugin} "$HOME/.config/opencode/plugins/context-reinject.ts"
          $DRY_RUN_CMD cp -f ${../devlogs-lib/devlogs.ts} "$HOME/.config/opencode/plugins/devlogs.ts"
          $DRY_RUN_CMD cp -f ${tokenCounterPlugin} "$HOME/.config/opencode/plugins/token-counter.tsx"
        '';
      };
    };
  };
}
