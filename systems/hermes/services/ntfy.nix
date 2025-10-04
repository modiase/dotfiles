{
  config,
  pkgs,
  rootDomain,
  ...
}:

{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${rootDomain}";
      listen-http = ":8080";
      behind-proxy = true;
    };
  };
}
