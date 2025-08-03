# usage: sandbox [--keep|-k]
set --local keep_volume 0
argparse k/keep -- $argv
if set -q _flag_keep
    set keep_volume 1
end

set --local volume_name sandbox-(random)

set --local arch (uname -m)
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

if test (uname) = Darwin
    # Create a temporary sandbox directory on macOS (persist beyond this block)
    set sandbox_dir (mktemp -d /tmp/$volume_name-XXXXXX)
    echo "Created sandbox directory: $sandbox_dir"
else
    docker volume create $volume_name
    echo "Created volume: $volume_name"
    set sandbox_dir $volume_name
end

set --local nix_config "extra-experimental-features = nix-command flakes
extra-substituters = file:///host-store?trusted=1&nar-cache=/nix/store/nar"

if test (uname) = Darwin
    container run -it --remove \
        --mount "type=bind,source=$sandbox_dir,target=/sandbox" \
        --mount "type=bind,source=/nix,target=/host-store,readonly" \
        -w /sandbox \
        -e NIX_CONFIG="$nix_config" \
        -a $docker_arch \
        $image \
        sh
else
    docker run -it --rm \
        --volume "$sandbox_dir:/sandbox" \
        --volume "/nix:/host-store:ro" \
        --workdir /sandbox \
        --env NIX_CONFIG="$nix_config"
    $image \
        bash
end

# Cleanup sandbox storage if not keeping
if test $keep_volume -eq 0
    if test (uname) = Darwin
        rm -rf $sandbox_dir
    else
        docker volume rm $volume_name
    end
end
