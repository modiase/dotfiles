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
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://ntfy.${rootDomain}";
      listen-http = ":${toString ports.ntfy}";
      behind-proxy = true;
    };
  };
}
