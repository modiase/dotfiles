{ pkgs, ... }:

let
  script = pkgs.writeShellScript "firewall-logs-server.sh" ''
    set -euo pipefail

    SOCKET_PATH="/run/firewall-logs/logs.sock"
    SCRIPT_PATH="''${BASH_SOURCE[0]}"

    if [[ "''${1:-}" == "--generate" ]]; then
        journalctl -k -n 200 --no-pager -o short-iso 2>/dev/null | grep "FW_DROP:" || true
        exit 0
    fi

    rm -f "$SOCKET_PATH"

    socat UNIX-LISTEN:"$SOCKET_PATH",mode=0666,unlink-early,fork EXEC:"$SCRIPT_PATH --generate"
  '';
in
{
  systemd.services.firewall-logs-server = {
    description = "Firewall logs server for dashboard";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.socat
    ];
    serviceConfig = {
      ExecStart = "${script}";
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "firewall-logs";
    };
  };
}
