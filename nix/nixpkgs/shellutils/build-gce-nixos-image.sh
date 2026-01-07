# shellcheck shell=bash
set -euo pipefail

usage() {
    cat <<'USAGE'
Usage: build-gce-nixos-image --attr ATTR [--flake FLAKE-URI]
                             [--keep-build] [--remote-host HOST] [-v LEVEL]

Builds a NixOS GCE image and outputs the path to the built tarball.

Required:
  --attr ATTR        Nix attribute to build (e.g. nixosConfigurations.hermes.config.system.build.googleComputeImage)

Optional:
  --flake FLAKE      Flake URI to build (default: auto-detect from git)
  --keep-build       Leave the temporary build directory on disk
  --remote-host HOST Optional log hint that a remote builder HOST will execute the build
  -v LEVEL           Verbosity level: 1 (print build logs), 2 (bash tracing)

Example:
  build-gce-nixos-image \
    --attr nixosConfigurations.hermes.config.system.build.googleComputeImage \
    --flake /path/to/dotfiles \
    --remote-host herakles -v 1

Outputs the path to the built tarball on stdout.
USAGE
}

FLAKE_URI=""
IMAGE_ATTR=""
KEEP_BUILD=0
REMOTE_HOST=""
VERBOSE_LEVEL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --flake)
            FLAKE_URI="$2"
            shift 2
            ;;
        --attr)
            IMAGE_ATTR="$2"
            shift 2
            ;;
        --keep-build)
            KEEP_BUILD=1
            shift 1
            ;;
        --remote-host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        -v)
            VERBOSE_LEVEL="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$IMAGE_ATTR" ]]; then
    echo "Error: --attr is required" >&2
    usage
    exit 1
fi

if [[ -z "$FLAKE_URI" ]]; then
    FLAKE_URI="$(git rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$FLAKE_URI" ]]; then
        echo "Error: --flake is required (not in a git repository)" >&2
        usage
        exit 1
    fi
fi

if [[ $VERBOSE_LEVEL -ge 2 ]]; then
    set -x
fi

TMPDIR="$(mktemp -d)"
if [[ $KEEP_BUILD -eq 0 ]]; then
    trap 'rm -rf "$TMPDIR"' EXIT
else
    trap 'echo "Temporary build directory left at $TMPDIR"' EXIT
fi

export NIX_CONFIG="experimental-features = nix-command flakes"
if [[ -n "$REMOTE_HOST" ]]; then
    log_info "Remote builder: $REMOTE_HOST"
fi

pushd "$TMPDIR" >/dev/null
OUT_LINK="result-image"

NIX_CMD=(nix build "${FLAKE_URI}#${IMAGE_ATTR}" --max-jobs 0 --log-format raw)
if [[ -n "$REMOTE_HOST" ]]; then
    NIX_CMD+=(--store "ssh-ng://moye@${REMOTE_HOST}" --eval-store auto --system x86_64-linux --no-link --print-out-paths)
else
    NIX_CMD+=(--out-link "$OUT_LINK")
fi
if [[ $VERBOSE_LEVEL -ge 1 ]]; then
    NIX_CMD+=(--print-build-logs)
fi

if [[ -n "$REMOTE_HOST" ]]; then
    log_info "nix-build started"
    if ! REMOTE_OUT_PATH="$("${NIX_CMD[@]}" 2>&1 | tee >(cat >&2) | grep '^/nix/store' | head -1)"; then
        log_error "nix-build failed"
        exit 1
    fi
    log_success "nix-build completed"
    log_info "Copying result from remote store: $REMOTE_OUT_PATH"
    nix copy --from "ssh-ng://moye@${REMOTE_HOST}" "$REMOTE_OUT_PATH"
    OUT_PATH="$REMOTE_OUT_PATH"
else
    run_logged "nix-build" "${NIX_CMD[@]}"
    OUT_PATH="$(realpath "$TMPDIR/$OUT_LINK")"
fi

popd >/dev/null
if [[ -d "$OUT_PATH" ]]; then
    TARBALL_PATH="$(find "$OUT_PATH" -maxdepth 1 -type f -name '*.tar.gz' | head -n1)"
else
    TARBALL_PATH="$OUT_PATH"
fi

if [[ -z "$TARBALL_PATH" || ! -f "$TARBALL_PATH" ]]; then
    echo "Expected tarball not found inside $OUT_PATH" >&2
    exit 1
fi

echo "BUILD_RESULT: $TARBALL_PATH"

if [[ $KEEP_BUILD -eq 1 ]]; then
    log_info "Build artifacts remain in $TMPDIR" >&2
fi

if [[ $VERBOSE_LEVEL -ge 1 ]]; then
    log_success "Image built successfully: $TARBALL_PATH" >&2
fi
