{
  config,
  pkgs,
  rootDomain,
  ...
}:

{
  services.n8n = {
    enable = true;
    webhookUrl = "https://n8n.${rootDomain}/";
    settings = {
      host = "127.0.0.1";
      port = 5678;
      protocol = "https";
      editorBaseUrl = "https://n8n.${rootDomain}/";
    };
  };

}
