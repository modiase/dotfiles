set --local keep_volume 0
argparse k/keep -- $argv
if set -q _flag_keep
    set keep_volume 1
end

set --local volume_name "sandbox-"(random)

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

docker volume create $volume_name
echo "Created volume: $volume_name"

docker run -it --rm \
    -v "$volume_name:/sandbox" \
    -v "/nix/store:/host-store:ro" \
    -w /sandbox \
    -e NIX_CONFIG="extra-experimental-features = nix-command flakes
extra-substituters = file:///host-store?trusted=1" \
    $image \
    bash

if [ $keep_volume -eq 0 ]
    docker volume rm $volume_name
end
