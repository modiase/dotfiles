#!/usr/bin/env bash
set -eu

input=$(cat)

file_path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
    clog debug "no file_path in tool_input, skipping"
    exit 0
fi

if [[ "${CLAUDE_FORMAT_DISABLED:-}" == "1" ]]; then
    clog debug "formatting disabled via CLAUDE_FORMAT_DISABLED"
    exit 0
fi

if [[ ! -f "$file_path" ]]; then
    clog debug "file does not exist: $file_path"
    exit 0
fi

ext="${file_path##*.}"
basename="${file_path##*/}"

if [[ -n "${CLAUDE_FORMAT_SKIP:-}" ]]; then
    IFS=',' read -ra skips <<<"$CLAUDE_FORMAT_SKIP"
    for s in "${skips[@]}"; do
        if [[ "$s" == "$ext" ]]; then
            clog debug "skipping $ext (CLAUDE_FORMAT_SKIP)"
            exit 0
        fi
    done
fi

ext_upper=$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')
override_var="CLAUDE_FORMAT_${ext_upper}"

if [[ -n "${!override_var:-}" ]]; then
    override="${!override_var}"
    if [[ "$override" == "false" ]]; then
        clog debug "formatter disabled for .$ext via $override_var=false"
        exit 0
    fi
    clog info "formatting $file_path with override: $override"
    eval "$override \"\$file_path\"" || true
    exit 0
fi

run_formatter() {
    local cmd="$1" pkg="$2"
    shift 2
    if command -v "$cmd" >/dev/null 2>&1; then
        "$cmd" "$@" || true
    else
        clog info "$cmd not in PATH, falling back to nix shell nixpkgs#$pkg"
        nix shell "nixpkgs#$pkg" -c "$cmd" "$@" || true
    fi
}

case "$basename" in
    BUILD | BUILD.* | WORKSPACE | WORKSPACE.*)
        clog info "formatting $file_path with buildifier"
        run_formatter buildifier buildifier "$file_path"
        exit 0
        ;;
esac

case "$ext" in
    nix)
        clog info "formatting $file_path with nixfmt"
        run_formatter statix statix fix "$file_path"
        run_formatter nixfmt nixfmt "$file_path"
        ;;
    lua)
        clog info "formatting $file_path with stylua"
        run_formatter stylua stylua "$file_path"
        ;;
    fish)
        clog info "formatting $file_path with fish_indent"
        run_formatter fish_indent fish -w "$file_path"
        ;;
    go)
        clog info "formatting $file_path with gofmt"
        run_formatter gofmt go -w "$file_path"
        ;;
    py)
        clog info "formatting $file_path with ruff"
        run_formatter ruff ruff check --fix "$file_path"
        run_formatter ruff ruff format "$file_path"
        ;;
    sh | bash)
        clog info "formatting $file_path with shfmt"
        run_formatter shfmt shfmt -w -i 4 -ci "$file_path"
        ;;
    ts | js | jsx | tsx)
        clog info "formatting $file_path with biome"
        run_formatter biome biome check --fix --unsafe "$file_path"
        ;;
    json)
        clog info "formatting $file_path with biome"
        run_formatter biome biome format --write "$file_path"
        ;;
    css | scss)
        clog info "formatting $file_path with biome"
        run_formatter biome biome check --fix --unsafe "$file_path"
        ;;
    java)
        clog info "formatting $file_path with google-java-format"
        run_formatter google-java-format google-java-format --replace "$file_path"
        ;;
    rs)
        clog info "formatting $file_path with rustfmt"
        run_formatter rustfmt rustfmt "$file_path"
        ;;
    bzl)
        clog info "formatting $file_path with buildifier"
        run_formatter buildifier buildifier "$file_path"
        ;;
    tofu | hcl | tf)
        clog info "formatting $file_path with tofu"
        run_formatter tofu opentofu fmt "$file_path"
        ;;
    yaml | yml)
        clog info "formatting $file_path with prettier"
        run_formatter prettier prettier --write "$file_path"
        ;;
    html)
        clog info "formatting $file_path with prettier"
        run_formatter prettier prettier --write "$file_path"
        ;;
    md)
        clog info "formatting $file_path with prettier"
        run_formatter prettier prettier --write --prose-wrap preserve "$file_path"
        ;;
    *)
        clog debug "no default formatter for .$ext"
        ;;
esac

exit 0
