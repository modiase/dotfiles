{
  config,
  options,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.auto-activate;
  isDarwin = options ? launchd;
  homeDir = if isDarwin then "/Users/moye" else "/home/moye";
  activatePath = "${homeDir}/dotfiles/bin/activate";

  secrets = pkgs.callPackage ./nixpkgs/secrets { };
  attn = pkgs.callPackage ./nixpkgs/attn { };
  ntfy-me = pkgs.callPackage ./nixpkgs/ntfy-me { inherit secrets attn; };

  wrapper = pkgs.writeShellApplication {
    name = "auto-activate";
    runtimeInputs = [
      pkgs.bashInteractive
      pkgs.coreutils
      pkgs.flock
      pkgs.git
      pkgs.inetutils
      ntfy-me
    ];
    text = ''
      if ${activatePath}; then
        ntfy-me -t jobs -p 2 -T "Auto-activate" "$(hostname -s) activated successfully"
      else
        ntfy-me -t jobs -p 4 -T "Auto-activate" "$(hostname -s) activation failed"
        exit 1
      fi
    '';
  };
in

{
  options.services.auto-activate = {
    enable = lib.mkEnableOption "daily dotfiles auto-activation";
  };

  config = lib.mkIf cfg.enable (
    if isDarwin then
      {
        launchd.daemons.auto-activate = {
          serviceConfig = {
            ProgramArguments = [ "${wrapper}/bin/auto-activate" ];
            StartCalendarInterval = [
              {
                Hour = 3;
                Minute = 0;
              }
            ];
            UserName = "moye";
            StandardOutPath = "/tmp/auto-activate.log";
            StandardErrorPath = "/tmp/auto-activate.err";
          };
        };
      }
    else
      {
        systemd.timers.auto-activate = {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnCalendar = "*-*-* 03:00:00";
            Persistent = true;
            RandomizedDelaySec = "10min";
          };
        };

        systemd.services.auto-activate = {
          description = "Pull latest dotfiles and activate";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            User = "moye";
            ExecStart = "${wrapper}/bin/auto-activate";
            TimeoutStartSec = "30min";
          };
        };
      }
  );
}
