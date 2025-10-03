{
  config,
  pkgs,
  domain,
  ...
}:

{
  services.n8n = {
    enable = true;
    webhookUrl = "https://n8n.${domain}/";
    settings = {
      host = "127.0.0.1";
      port = 5678;
      protocol = "https";
      editorBaseUrl = "https://n8n.${domain}/";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/n8n 0750 n8n n8n -"
  ];
}
