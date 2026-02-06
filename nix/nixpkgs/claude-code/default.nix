{
  config,
  lib,
  pkgs,
  nvim-mcp ? null,
  ...
}:
let
  nvim-mcp-connect =
    if nvim-mcp != null then pkgs.callPackage ../nvim-mcp-connect { inherit nvim-mcp; } else null;
  settings = import ./settings.nix;
  mcpServers = lib.optionalAttrs (nvim-mcp-connect != null) {
    nvim = {
      type = "stdio";
      command = "${nvim-mcp-connect}/bin/nvim-mcp-connect";
      env = {
        TMUX = "\${TMUX:-}";
      };
    };
  };
  mcpServersJson = pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON mcpServers);
in
{
  config = lib.mkIf config.programs.claude-code.enable {
    programs.claude-code.settings = settings;
    home.file.".claude/CLAUDE.md".source = ./CLAUDE.md;

    home.activation.claudeMcpServers = lib.mkIf (mcpServers != { }) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        claude_json="$HOME/.claude.json"
        if [[ -f "$claude_json" ]]; then
          ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: ((.[0].mcpServers // {}) * .[1])}' \
            "$claude_json" ${mcpServersJson} > "$claude_json.tmp" && mv "$claude_json.tmp" "$claude_json"
        else
          echo '{}' | ${pkgs.jq}/bin/jq -s '.[0] * {mcpServers: .[1]}' - ${mcpServersJson} > "$claude_json"
        fi
      ''
    );
  };
}
