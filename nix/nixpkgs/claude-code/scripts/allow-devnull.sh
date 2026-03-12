# shellcheck shell=bash
INPUT=$(cat)

_DEVLOGS_WIN=""
if [[ -n "${TMUX_PANE:-}" ]]; then
    _DEVLOGS_WIN=$(tmux display-message -t "$TMUX_PANE" -p '#{window_index}' 2>/dev/null) || true
fi

clog() {
    local level="$1"
    shift
    local win=""
    if [[ -n "$_DEVLOGS_WIN" ]]; then win="(@$_DEVLOGS_WIN)"; fi
    logger -t devlogs -p "user.$level" "[devlogs] ${level^^} allow-devnull${win}: $*"
}

cmd=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0 || true

clog debug "checking cmd=$cmd"

[[ "$cmd" != *"/dev/null"* && "$cmd" != *">&"* ]] && exit 0 || true

# fd duplications (2>&1) stripped first so subsequent rules can match residual redirects
clean=$(echo "$cmd" | sed \
    -e 's|[0-9]*>&[0-9]*||g' \
    -e 's|&>>[[:space:]]*/dev/null||g' \
    -e 's|&>[[:space:]]*/dev/null||g' \
    -e 's|[0-9]*>>[[:space:]]*/dev/null||g' \
    -e 's|[0-9]*>[[:space:]]*/dev/null||g' \
    -e 's|[[:space:]]*$||')

[[ -z "$clean" ]] && exit 0 || true

settings_file="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
[[ ! -f "$settings_file" ]] && exit 0 || true

extract_patterns() {
    jq -r "(.permissions.${1} // [])[]" "$settings_file" 2>/dev/null |
        sed -n 's/^Bash(\(.*\))$/\1/p' |
        sed 's/:\*/*/g' ||
        true
}

while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue || true
    # shellcheck disable=SC2053
    [[ "$clean" == $pattern ]] && exit 0 || true
done < <(extract_patterns deny)

while IFS= read -r pattern; do
    [[ -z "$pattern" ]] && continue || true
    # shellcheck disable=SC2053
    if [[ "$clean" == $pattern ]]; then
        clog info "allowed cmd=$clean"
        echo '{"permissionDecision":"allow"}'
        exit 0
    fi
done < <(extract_patterns allow)
