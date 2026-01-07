{ pkgs, ... }:

{
  systemd.services.ssh-logger = {
    description = "SSH connection logger";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bash}/bin/bash -c 'journalctl -f -u sshd | tee -a /var/log/ssh-access.log'";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  services.logrotate = {
    enable = true;
    settings = {
      "/var/log/ssh-access.log" = {
        frequency = "daily";
        rotate = 7;
        compress = true;
        delaycompress = true;
        missingok = true;
        notifempty = true;
        postrotate = "systemctl reload rsyslog";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "f /var/log/ssh-access.log 0644 root root - -"
  ];
}
