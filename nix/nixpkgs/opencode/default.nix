{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.dotfiles.opencode;

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

  opencodeConfig = pkgs.writeText "opencode.json" (
    builtins.toJSON {
      "$schema" = "https://opencode.ai/config.json";
      autoupdate = false;
      plugin = [
        "${homeDir}/.config/opencode/plugins/plan-review.ts"
        "${homeDir}/.config/opencode/plugins/notify.ts"
      ];
      agent.plan.prompt = "You may use the question tool to ask the user clarifying questions before writing a plan. Once your plan is ready, you MUST call the submit_plan tool — do NOT present the plan in chat. Format every actionable item as a markdown checkbox (- [ ] item). If the user rejects, revise based on their feedback and call submit_plan again. NEVER proceed to implementation without plan approval via submit_plan.";
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
      packages = [ pkgs.opencode ];

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
