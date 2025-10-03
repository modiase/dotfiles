#!/usr/bin/env nix-shell
#!nix-shell -i bash -p git google-cloud-sdk coreutils cacert

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: build-gce-nixos-image.sh --attr ATTR [--dest gs://bucket/path.tar.gz]
                                [--flake FLAKE-URI]
                                [--keep-build] [--remote-host HOST]

Environment variables:
  PROJECT_ID      Optional (default: modiase-infra). Passed to gsutil via GSUtil:default_project_id.

Required:
  --attr ATTR        Nix attribute to build (e.g. nixosConfigurations.hermes.config.system.build.googleComputeImage)

Optional:
  --dest URI         Destination gs:// path for the tarball (default: gs://modiase-infra/images/base-nixos-latest-x86_64.tar.gz)
  --flake FLAKE      Flake URI to build (default: repo root)
  --keep-build       Leave the temporary build directory on disk
  --remote-host HOST Optional log hint that a remote builder HOST will execute the build

Example (Hermes):
  PROJECT_ID=modiase-infra ./bin/build-gce-nixos-image.sh \\
    --attr nixosConfigurations.hermes.config.system.build.googleComputeImage \\
    --dest gs://modiase-infra/images/hermes-nixos-latest.tar.gz \\
    --remote-host herakles

Without --dest the helper uploads a generic base image to gs://modiase-infra/images/base-nixos-latest-x86_64.tar.gz.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOG_LEVEL=${LOG_LEVEL:-2}
COLOR_ENABLED=${COLOR_ENABLED:-true}
source "$SCRIPT_DIR/lib.sh"

DEST_URI="gs://modiase-infra/images/base-nixos-latest_x86_64.tar.gz"
PROJECT_ID="${PROJECT_ID:-modiase-infra}"
FLAKE_URI="$REPO_ROOT"
IMAGE_ATTR=""
KEEP_BUILD=0
REMOTE_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      DEST_URI="$2"; shift 2;
      ;;
    --flake)
      FLAKE_URI="$2"; shift 2;
      ;;
    --attr)
      IMAGE_ATTR="$2"; shift 2;
      ;;
    --keep-build)
      KEEP_BUILD=1; shift 1;
      ;;
    --remote-host)
      REMOTE_HOST="$2"; shift 2;
      ;;
    -h|--help)
      usage; exit 0;
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
run_logged "nix-build" "$COLOR_WHITE" \
  nix build "${FLAKE_URI}#${IMAGE_ATTR}" --out-link "$OUT_LINK" --max-jobs 0 --cores 0
popd >/dev/null

OUT_PATH="$(realpath "$TMPDIR/$OUT_LINK")"
if [[ -d "$OUT_PATH" ]]; then
  TARBALL_PATH="$(find "$OUT_PATH" -maxdepth 1 -type f -name '*.tar.gz' | head -n1)"
else
  TARBALL_PATH="$OUT_PATH"
fi

if [[ -z "$TARBALL_PATH" || ! -f "$TARBALL_PATH" ]]; then
  echo "Expected tarball not found inside $OUT_PATH" >&2
  exit 1
fi

BASENAME="$(basename "$DEST_URI")"
LOCAL_COPY="$TMPDIR/$BASENAME"
cp "$TARBALL_PATH" "$LOCAL_COPY"

cat > "$TMPDIR/image-metadata.json" <<JSON
{
  "flake": "${FLAKE_URI}",
  "attribute": "${IMAGE_ATTR}",
  "gitRevision": "$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null || echo unknown)",
  "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON

log_info "Prepared metadata for ${IMAGE_ATTR} (revision $(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo unknown))"

GSUTIL=(gsutil)
if [[ -n "${PROJECT_ID:-}" ]]; then
  GSUTIL+=( -o "GSUtil:default_project_id=${PROJECT_ID}" )
fi

run_logged "upload-tar" "$COLOR_WHITE" env GSUTIL_PARALLEL_COMPOSITE_UPLOAD_THRESHOLD=150M "${GSUTIL[@]}" cp "$LOCAL_COPY" "$DEST_URI"

METADATA_URI="${DEST_URI%.tar.gz}.json"
if ! run_logged "upload-metadata" "$COLOR_WHITE" env GSUTIL_PARALLEL_COMPOSITE_UPLOAD_THRESHOLD=150M "${GSUTIL[@]}" cp "$TMPDIR/image-metadata.json" "$METADATA_URI"; then
  log_error "Failed to upload metadata to $METADATA_URI"
  exit 1
fi

if [[ $KEEP_BUILD -eq 1 ]]; then
  log_info "Build artifacts remain in $TMPDIR"
fi

log_success "Image available at ${DEST_URI}"
