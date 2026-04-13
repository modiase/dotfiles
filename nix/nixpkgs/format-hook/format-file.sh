# shellcheck shell=bash
format_file() {
    local file_path="$1"

    if [[ "${FORMAT_HOOK_DISABLED:-}" == "1" ]]; then
        clog debug "formatting disabled via FORMAT_HOOK_DISABLED"
        return 0
    fi

    if [[ -n "${FORMAT_HOOK_OVERRIDE:-}" ]]; then
        if "$FORMAT_HOOK_OVERRIDE" "$file_path" 2>/dev/null; then
            clog debug "formatted by override: $FORMAT_HOOK_OVERRIDE"
            return 0
        fi
    fi

    if [[ ! -f "$file_path" ]]; then
        clog debug "file does not exist: $file_path"
        return 0
    fi

    local ext="${file_path##*.}"
    local basename="${file_path##*/}"

    if [[ -n "${FORMAT_HOOK_SKIP:-}" ]]; then
        IFS=',' read -ra skips <<<"$FORMAT_HOOK_SKIP"
        local s
        for s in "${skips[@]}"; do
            if [[ "$s" == "$ext" ]]; then
                clog debug "skipping $ext (FORMAT_HOOK_SKIP)"
                return 0
            fi
        done
    fi

    local ext_upper
    ext_upper=$(printf '%s' "$ext" | tr '[:lower:]' '[:upper:]')
    local override_var="FORMAT_HOOK_${ext_upper}"

    if [[ -n "${!override_var:-}" ]]; then
        local override="${!override_var}"
        if [[ "$override" == "false" ]]; then
            clog debug "formatter disabled for .$ext via $override_var=false"
            return 0
        fi
        clog info "formatting $file_path with override: $override"
        eval "$override \"\$file_path\"" || true
        return 0
    fi

    run_formatter() {
        local cmd="$1"
        shift
        clog debug "formatting $file_path with $cmd $*"
        "$cmd" "$@" || true
    }

    case "$basename" in
        BUILD | BUILD.* | WORKSPACE | WORKSPACE.*)
            run_formatter buildifier "$file_path"
            return 0
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
}
