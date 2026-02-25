sops-edit *args:
    #!/usr/bin/env bash
    set -euo pipefail
    SOPS_AGE_KEY="$(secrets get dotfiles-age-key --network --print)"
    export SOPS_AGE_KEY
    sops="$(nix build nixpkgs#sops --no-link --print-out-paths 2>/dev/null)/bin/sops"
    EDITOR=vi "$sops" {{ args }}

pre-commit:
    #!/usr/bin/env bash
    set -euo pipefail
    staged=$(git diff --cached --name-only --diff-filter d)
    [[ -z "$staged" ]] && exit 0

    has() { echo "$staged" | grep -qE "$1"; }

    pids=()
    labels=()
    run() {
        just "$1" > "/tmp/pre-commit-$1.log" 2>&1 &
        pids+=($!)
        labels+=("$1")
    }

    if has '\.nix$'; then run pre-commit-nix; fi
    if has '\.lua$'; then run pre-commit-lua; fi
    if has '\.fish$'; then run pre-commit-fish; fi
    if has '\.go$'; then run pre-commit-go; fi
    if has '\.py$'; then run pre-commit-python; fi
    if has 'systems/hekate/run/dashboard/webui/src/.*\.(ts|html)$'; then run pre-commit-typescript; fi
    if has '\.(sh|bash)$|^bin/'; then run pre-commit-shell; fi
    if has '^infra/.*\.tofu$'; then run pre-commit-terraform; fi
    run pre-commit-whitespace

    failed=0
    for i in "${!pids[@]}"; do
        if ! wait "${pids[$i]}"; then
            printf '\n\033[1;31m✗ %s\033[0m\n' "${labels[$i]}"
            cat "/tmp/pre-commit-${labels[$i]}.log"
            failed=1
        else
            printf '\033[1;32m✓ %s\033[0m\n' "${labels[$i]}"
        fi
    done
    exit $failed

pre-commit-nix:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep '\.nix$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    # shellcheck disable=SC2086
    nix-shell -p nixfmt --run "nixfmt ${files[*]}"
    nix --extra-experimental-features 'nix-command flakes' flake show --no-write-lock-file &>/dev/null

pre-commit-lua:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep '\.lua$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    # shellcheck disable=SC2086
    nix-shell -p stylua --run "stylua ${files[*]}"

pre-commit-fish:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep '\.fish$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    export STAGED_FISH="${files[*]}"
    nix-shell -p fish --run 'set -euo pipefail
    # shellcheck disable=SC2086
    fish_indent -w $STAGED_FISH
    for f in $STAGED_FISH; do fish --no-execute "$f"; done
    '

pre-commit-go:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep '\.go$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    declare -A modules
    for f in "${files[@]}"; do
        dir=$(dirname "$f")
        while [[ "$dir" != '.' && ! -f "$dir/go.mod" ]]; do dir=$(dirname "$dir"); done
        if [[ -f "$dir/go.mod" ]]; then modules["$dir"]=1; fi
    done
    export STAGED_GO="${files[*]}"
    export GO_MODULES="${!modules[*]}"
    nix-shell -p go golangci-lint --run 'set -euo pipefail
    # shellcheck disable=SC2086
    gofmt -w $STAGED_GO
    for mod in $GO_MODULES; do (cd "$mod" && golangci-lint run ./...); done
    '

pre-commit-python:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep '\.py$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    # shellcheck disable=SC2086
    nix-shell -p ruff --run "ruff check --fix ${files[*]} && ruff format ${files[*]}"

pre-commit-typescript:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep -E '^systems/hekate/run/dashboard/webui/src/.*\.(ts|html)$')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    cd systems/hekate/run/dashboard/webui
    pnpm run lint
    mapfile -t ts_files < <(printf '%s\n' "${files[@]}" | grep '\.ts$' | sed 's|^systems/hekate/run/dashboard/webui/||')
    if [[ ${#ts_files[@]} -gt 0 ]]; then
        # shellcheck disable=SC2086
        pnpm dlx organize-imports-cli ${ts_files[*]}
    fi

pre-commit-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep -E '\.(sh|bash)$|^bin/')
    [[ ${#files[@]} -eq 0 ]] && exit 0
    export STAGED_SH="${files[*]}"
    nix-shell -p shfmt shellcheck --run 'set -euo pipefail
    # shellcheck disable=SC2086
    shfmt -w -i 4 -ci $STAGED_SH
    for f in $STAGED_SH; do bash -n "$f"; done
    # shellcheck disable=SC2086
    shellcheck $STAGED_SH
    '

pre-commit-terraform:
    #!/usr/bin/env bash
    set -euo pipefail
    nix-shell -p opentofu --run 'cd infra && tofu fmt'

pre-commit-whitespace:
    #!/usr/bin/env bash
    set -euo pipefail
    mapfile -t files < <(git diff --cached --name-only --diff-filter d | grep -vE '\.(png|ico|jpg|jpeg|gif|webp|woff|woff2|ttf|eot|pdf)$' || true)
    [[ ${#files[@]} -eq 0 ]] && exit 0
    # shellcheck disable=SC2086
    nix-shell -p gnused --run "sed -i 's/[[:space:]]*$//' ${files[*]}"

nix-lint:
    #!/usr/bin/env bash
    set -euo pipefail
    nix-shell -p deadnix statix fd --run 'set -euo pipefail
    fd -e nix -E worktrees | xargs -r deadnix
    for d in nix systems lib; do if [ -d "$d" ]; then statix check "$d"; fi; done
    statix check flake.nix
    '

post-checkout:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "$(git branch --show-current)" = "main" ]; then
        git branch --merged main | grep -v main | xargs -r git branch -d
    fi
