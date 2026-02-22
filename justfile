sops-edit *args:
    #!/usr/bin/env bash
    set -euo pipefail
    SOPS_AGE_KEY="$(secrets get dotfiles-age-key --network --print)"
    export SOPS_AGE_KEY
    sops="$(nix build nixpkgs#sops --no-link --print-out-paths 2>/dev/null)/bin/sops"
    EDITOR=vi "$sops" {{ args }}
