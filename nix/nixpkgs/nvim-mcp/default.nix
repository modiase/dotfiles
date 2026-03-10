{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage rec {
  pname = "nvim-mcp";
  version = "0.7.2";

  src = fetchFromGitHub {
    owner = "linw1995";
    repo = "nvim-mcp";
    rev = "v${version}";
    hash = "sha256-T9nLYwiVnX5mIoNsivYNbdFlG6Qd6xAJiWHcsC+AHxk=";
  };

  cargoHash = "sha256-Sq/AfycROtf8OCHm880FC9uYttN/dp24j7N0UjipH44=";

  doCheck = false;
}
