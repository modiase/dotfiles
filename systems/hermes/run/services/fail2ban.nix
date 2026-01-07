{ ... }:

{
  services.fail2ban = {
    enable = true;
    bantime-increment.enable = true;
    jails = {
      ssh.settings = {
        maxretry = 3;
        bantime = "1h";
        findtime = "10m";
      };
      authelia.settings = {
        journalmatch = "_SYSTEMD_UNIT=authelia.service";
        filter = "authelia";
        maxretry = 3;
        bantime = "1h";
        findtime = "10m";
      };
      nginx-limit-req.settings = {
        journalmatch = "_SYSTEMD_UNIT=nginx.service";
        maxretry = 5;
        bantime = "10m";
        findtime = "2m";
      };
    };
  };

  environment.etc."fail2ban/filter.d/authelia.conf".text = ''
    [Definition]
    failregex = ^.*Unsuccessful (1FA|TOTP|Duo|U2F) authentication attempt by user .*remote_ip"?(:|=)"?<HOST>"?.*$
                ^.*user not found.*path=/api/reset-password/identity/start remote_ip"?(:|=)"?<HOST>"?.*$
                ^.*Sending an email to user.*path=/api/.*/start remote_ip"?(:|=)"?<HOST>"?.*$

    ignoreregex = ^.*level"?(:|=)"?info.*
                  ^.*level"?(:|=)"?warning.*
  '';
}
