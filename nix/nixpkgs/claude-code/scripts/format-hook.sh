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
    local cmd="$1"
    shift
    clog debug "formatting $file_path with $cmd"
    "$cmd" "$@" || true
}

case "$basename" in
    BUILD | BUILD.* | WORKSPACE | WORKSPACE.*)
        run_formatter buildifier "$file_path"
        exit 0
        ;;
esac

case "$ext" in
    nix)
        run_formatter statix fix "$file_path"
        run_formatter nixfmt "$file_path"
        ;;
    lua) run_formatter stylua "$file_path" ;;
    fish) run_formatter fish_indent -w "$file_path" ;;
    go) run_formatter gofmt -w "$file_path" ;;
    py)
        run_formatter ruff check --fix "$file_path"
        run_formatter ruff format "$file_path"
        ;;
    sh | bash) run_formatter shfmt -w -i 4 -ci "$file_path" ;;
    ts | js | jsx | tsx)
        run_formatter biome check --fix --unsafe "$file_path"
        ;;
    json) run_formatter biome format --write "$file_path" ;;
    css | scss) run_formatter biome check --fix --unsafe "$file_path" ;;
    java) run_formatter google-java-format --replace "$file_path" ;;
    rs) run_formatter rustfmt "$file_path" ;;
    bzl) run_formatter buildifier "$file_path" ;;
    tofu | hcl | tf) run_formatter tofu fmt "$file_path" ;;
    yaml | yml) run_formatter prettier --write "$file_path" ;;
    html) run_formatter prettier --write "$file_path" ;;
    md) run_formatter prettier --write --prose-wrap preserve "$file_path" ;;
    *) clog debug "no default formatter for .$ext" ;;
esac

exit 0
