#
# Creates a temporary sandbox environment using a NixOS Docker container.
#
# Usage:
#   sandbox       - Create a sandbox and destroy it on exit.
#   sandbox -k    - Create a sandbox and keep the directory on exit.
#

set --local keep_dir 0
argparse k/keep -- $argv
if set -q _flag_keep
    set keep_dir 1
end

set --local sandbox_dir (mktemp -d)
echo "Created sandbox at: $sandbox_dir"

set --local flake_content '{
  description = "A development environment with Neovim";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell {
        buildInputs = [
          pkgs.bashInteractive
          pkgs.neovim
        ];
      };
    };
}
'
printf '%s\n' $flake_content >"$sandbox_dir/flake.nix"

set --local arch (uname -m)

set --local docker_arch
switch $arch
    case x86_64
        set docker_arch amd64
    case aarch64 arm64
        set docker_arch arm64
    case '*'
        echo "Unsupported architecture: $arch"
        return 1
end

set --local image "moyeodiase/nix-sandbox:$docker_arch"
echo "Using image: $image"

docker run -it --rm \
    -v "$sandbox_dir:/sandbox" \
    -v "/nix/store:/host-store:ro" \
    -w /sandbox \
    -e NIX_CONFIG="extra-experimental-features = nix-command flakes
extra-substituters = file:///host-store?trusted=1" \
    $image \
    bash

if [ $keep_dir -eq 0 ]
    rm -rf "$sandbox_dir"
end
