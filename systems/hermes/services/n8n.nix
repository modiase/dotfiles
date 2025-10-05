{
  config,
  pkgs,
  rootDomain,
  ...
}:

let
  ports = import ../ports.nix;
in

{
  environment.etc."n8n/hooks.js" = {
    source = ./n8n-hooks.js;
    mode = "0644";
  };

  environment.etc."n8n/setup.py" = {
    source = ./n8n-setup.py;
    mode = "0755";
  };

  services.n8n = {
    enable = true;
    webhookUrl = "https://n8n.${rootDomain}/";
    settings = {
      port = ports.n8n;
      protocol = "https";
      editorBaseUrl = "https://n8n.${rootDomain}/";
      nodes_include = "['n8n-nodes-*']";
      external_hook_files = "/etc/n8n/hooks.js";
    };
  };

  systemd.services.n8n = {
    serviceConfig.ReadOnlyPaths = [ "/etc/n8n" ];
    postStart = ''
      ${pkgs.coreutils}/bin/timeout 60 ${pkgs.bash}/bin/bash -c '
        while [ ! -f /var/lib/private/n8n/.n8n/database.sqlite ] || ! ${pkgs.curl}/bin/curl -s http://127.0.0.1:${toString ports.n8n}/ > /dev/null 2>&1; do
          sleep 2
        done
      '
      ${
        pkgs.python3.withPackages (ps: with ps; [ bcrypt ])
      }/bin/python /etc/n8n/setup.py "$(${pkgs.google-cloud-sdk}/bin/gcloud secrets versions access latest --secret="n8n-password" --project="modiase-infra")"
    '';
  };
}
