{
  config,
  pkgs,
  domain,
  ...
}:

{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${domain}";
      listen-http = ":8080";
      behind-proxy = true;
    };
  };
}
