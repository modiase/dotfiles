{
  pkgs ? import <nixpkgs> { },
}:

pkgs.buildGoModule {
  pname = "hekate-dashboard";
  version = "0.1.0";

  src = ./.;

  proxyVendor = true;
  vendorHash = "sha256-83YEIbFmsDLTB6uEhvF1q5xAITVy9DWWxEOy+JhGuRE=";

  meta = with pkgs.lib; {
    description = "Secure monitoring dashboard for Hekate VPN gateway";
    homepage = "https://github.com/moye/hekate-dashboard";
    license = licenses.mit;
    mainProgram = "hekate-dashboard";
  };
}
