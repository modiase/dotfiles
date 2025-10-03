#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOG_LEVEL=${LOG_LEVEL:-2}
COLOR_ENABLED=${COLOR_ENABLED:-true}
LOGGING_NO_PREFIX=${LOGGING_NO_PREFIX:-0}
source "$SCRIPT_DIR/lib.sh"
COLOR_CYAN="$COLOR_WHITE"

PROJECT_ID="${PROJECT_ID:-modiase-infra}"
DEST_URI="gs://modiase-infra/images/hermes-nixos-latest.tar.gz"
IMAGE_ATTR="nixosConfigurations.hermes.config.system.build.googleComputeImage"
REMOTE_HOST="herakles"
TF_VAR_FILE="$REPO_ROOT/infra/tofu.tfvars"

run_logged "build-image" "$COLOR_WHITE" \
  env PROJECT_ID="$PROJECT_ID" "$SCRIPT_DIR/build-gce-nixos-image.sh" \
    --attr "$IMAGE_ATTR" \
    --dest "$DEST_URI" \
    --remote-host "$REMOTE_HOST"

pushd "$REPO_ROOT/infra" >/dev/null

if ! run_logged "taint-image" "$COLOR_WHITE" tofu taint module.hermes.google_compute_image.hermes_nixos; then
  log_info "taint-image skipped (resource may not exist)"
fi

if ! run_logged "taint-instance" "$COLOR_WHITE" tofu taint module.hermes.google_compute_instance.hermes; then
  log_info "taint-instance skipped (resource may not exist)"
fi

run_logged "tofu-apply" "$COLOR_WHITE" tofu apply -auto-approve -var-file="$TF_VAR_FILE"

popd >/dev/null

log_success "Hermes image build and deploy complete."
