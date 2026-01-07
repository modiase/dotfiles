{ pkgs, ... }:

let
  script = pkgs.writeShellScript "dns-logs-server.sh" ''
    set -euo pipefail

    SOCKET_PATH="/run/dns-logs/logs.sock"
    SCRIPT_PATH="''${BASH_SOURCE[0]}"

    if [[ "''${1:-}" == "--generate" ]]; then
        journalctl -u unbound -n 100 --no-pager -o short-iso 2>/dev/null || echo "ERROR: Unable to read unbound logs"
        exit 0
    fi

    rm -f "$SOCKET_PATH"

    socat UNIX-LISTEN:"$SOCKET_PATH",mode=0666,unlink-early,fork EXEC:"$SCRIPT_PATH --generate"
  '';
in
{
  systemd.services.dns-logs-server = {
    description = "DNS logs server for dashboard";
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.coreutils
      pkgs.socat
    ];
    serviceConfig = {
      ExecStart = "${script}";
      Restart = "always";
      RestartSec = "5s";
      RuntimeDirectory = "dns-logs";
    };
  };
}
