# shellcheck shell=bash
PREFIX="secrets"
SCHEMA_PREFIX="modiase-secrets/v"
SCHEMA_VERSION="2"
SCHEMA="${SCHEMA_PREFIX}${SCHEMA_VERSION}"
SCHEMA_DIR="${SCHEMA_DIR:-}"
DEFAULT_ALGO="aes-256-cbc"
DEFAULT_ROUNDS=100000
DEFAULT_KEY_ALGO="pbkdf2"

SECRETSLIB_DIR="${SECRETS_DATA_DIR:-$HOME/.secretslib}"
MASTER_KEY_FILE="$SECRETSLIB_DIR/master-key"
HISTORY_FILE="$SECRETSLIB_DIR/history.jsonl"

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SQLITE_DB=""
TEST_PASSPHRASE=""
FORCE=false
DEBUG=false

debug_msg() {
    if [ "$DEBUG" = true ]; then echo "$@" >&2; fi
}

ensure_secretslib() {
    mkdir -p "$SECRETSLIB_DIR"
    chmod 700 "$SECRETSLIB_DIR"
    if [ ! -f "$MASTER_KEY_FILE" ]; then
        openssl rand -base64 32 >"$MASTER_KEY_FILE"
        chmod 600 "$MASTER_KEY_FILE"
    fi
    touch "$HISTORY_FILE"
}

get_master_key() {
    cat "$MASTER_KEY_FILE"
}

encrypt_with_master() {
    local value="$1"
    local key
    key=$(get_master_key)
    echo -n "$value" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$key" -base64 2>/dev/null
}

decrypt_with_master() {
    local encrypted="$1"
    local key
    key=$(get_master_key)
    echo "$encrypted" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass "pass:$key" -base64 2>/dev/null
}

log_operation() {
    local op="$1" name="$2" backend="$3" backup="${4:-}"
    local ts
    ts=$(date -Iseconds)
    if [ -n "$backup" ]; then
        jq -nc --arg ts "$ts" --arg op "$op" --arg name "$name" --arg backend "$backend" --arg backup "$backup" \
            '{ts: $ts, op: $op, name: $name, backend: $backend, backup: $backup}' >>"$HISTORY_FILE"
    else
        jq -nc --arg ts "$ts" --arg op "$op" --arg name "$name" --arg backend "$backend" \
            '{ts: $ts, op: $op, name: $name, backend: $backend}' >>"$HISTORY_FILE"
    fi
}

usage() {
    cat <<'EOF'
Usage: secrets <command> [OPTIONS]

A unified frontend for secrets management across platforms.
  - macOS: Uses Keychain via 'security' command (stored as secrets/NAME)
  - Linux: Uses 'pass' password store (stored as secrets/NAME)
  - Network: Uses Google Cloud Secret Manager (--network, requires gcloud auth)
  - SQLite: Uses local SQLite database (--sqlite PATH, for testing)

Commands:
  get NAME [OPTIONS]           Retrieve a secret
  store NAME [VALUE] [OPTIONS] Store a secret (prompts if VALUE omitted)
  delete NAME [OPTIONS]        Delete a secret (with confirmation)
  delete undo                  Restore the most recently deleted secret
  list [OPTIONS]               List available secrets
  log                          Show operation history (colourised)

Backend Flags:
  --local                 Use local backend (default)
  --network               Use Google Cloud Secret Manager
  --sqlite PATH           Use SQLite database at PATH
  --all                   Search both local and network

Get Options:
  --print                 Print to stdout (default if not a tty)
  --raw                   Return raw value without unwrapping JSON
  --no-env                Skip environment variable check
  --optional              Don't error if secret not found

By default, 'get' copies to clipboard when interactive (tty),
and prints to stdout when piped or used in scripts.

Store Options:
  --key                   Encrypt secret (prompts for passphrase)
  --algo ALGO             Encryption algorithm (default: aes-256-cbc)
  --rounds N              PBKDF2 iterations (default: 100000)
  --force                 Overwrite existing secret without confirmation
  (VALUE can be omitted to prompt securely)

Delete Options:
  --force                 Skip confirmation prompt

Testing Options:
  --passphrase PASS       Provide passphrase non-interactively
  --data-dir DIR          Use alternative secretslib directory

Common Options:
  --debug                 Show verbose backend messages
  --service SERVICE       Keychain service name (default: secrets/NAME)
  --account ACCOUNT       Keychain account (default: $USER)
  --pass-path PATH        Pass entry path (default: secrets/NAME)
  --project PROJECT       GCP project for --network (default: modiase-infra)
  -h, --help              Show this help

Examples:
  secrets get GEMINI_API_KEY                         # Get secret value
  secrets get GEMINI_API_KEY --print                 # Force print to stdout
  secrets store GEMINI_API_KEY                       # Prompt for value securely
  secrets store GEMINI_API_KEY --key                 # Store encrypted
  secrets delete OLD_API_KEY                         # Delete with confirmation
  secrets delete undo                                # Restore last deleted
  secrets get ANTHROPIC_API_KEY --network            # From GCP Secret Manager
  secrets list                                       # List local secrets
  secrets log                                        # Show operation history
EOF
}

copy_to_clipboard() {
    if [[ "$(uname)" == "Darwin" ]]; then
        pbcopy
    else
        local data
        data=$(base64 | tr -d '\n')
        printf '\033]52;c;%s\007' "$data"
    fi
}

check_gcloud_auth() {
    if ! gcloud auth print-access-token &>/dev/null; then
        echo "Error: Not authenticated with gcloud. Run 'gcloud auth login' first." >&2
        exit 1
    fi
}

init_sqlite() {
    local db="$1"
    sqlite3 "$db" "CREATE TABLE IF NOT EXISTS secrets (name TEXT PRIMARY KEY, value TEXT NOT NULL);"
}

get_sqlite() {
    local name="$1" db="$2"
    init_sqlite "$db"
    sqlite3 "$db" "SELECT value FROM secrets WHERE name = '$name';"
}

store_sqlite() {
    local name="$1" value="$2" db="$3"
    init_sqlite "$db"
    sqlite3 "$db" "INSERT OR REPLACE INTO secrets (name, value) VALUES ('$name', '$value');"
    debug_msg "Secret stored in SQLite database"
}

list_sqlite() {
    local db="$1"
    init_sqlite "$db"
    sqlite3 "$db" "SELECT name FROM secrets ORDER BY name;"
}

delete_sqlite() {
    local name="$1" db="$2"
    init_sqlite "$db"
    if sqlite3 "$db" "DELETE FROM secrets WHERE name = '$name'; SELECT changes();" | grep -q '^[1-9]'; then
        debug_msg "Secret deleted from SQLite database"
        return 0
    else
        echo "Error: $name not found in SQLite database" >&2
        return 1
    fi
}

is_wrapped_secret() {
    local value="$1"
    echo "$value" | jq -e --arg prefix "$SCHEMA_PREFIX" \
        'type == "object" and (.schema // "" | startswith($prefix))' >/dev/null 2>&1
}

validate_secret() {
    local raw="$1"
    local schema_version

    schema_version=$(echo "$raw" | jq -r '.schema // empty' | sed 's/.*\/v//')
    if [ -z "$schema_version" ]; then
        return 1
    fi

    if [ -n "$SCHEMA_DIR" ]; then
        local schema_file="$SCHEMA_DIR/v${schema_version}.json"
        if [ ! -f "$schema_file" ]; then
            echo "Error: Unknown schema version v$schema_version" >&2
            return 1
        fi
    fi

    if ! echo "$raw" | jq -e '.schema and .value' >/dev/null 2>&1; then
        echo "Error: Invalid secret format - missing required fields" >&2
        return 1
    fi

    return 0
}

prompt_passphrase() {
    local prompt_text="${1:-Enter passphrase}"
    if [ -n "$TEST_PASSPHRASE" ]; then
        echo "$TEST_PASSPHRASE"
        return 0
    fi
    local passphrase
    passphrase=$(gum input --password --placeholder "$prompt_text...")
    if [ -z "$passphrase" ]; then
        echo "Error: Empty passphrase not allowed" >&2
        return 1
    fi
    echo "$passphrase"
}

generate_salt() {
    openssl rand -hex 16
}

encrypt_value() {
    local value="$1" passphrase="$2" algo="${3:-$DEFAULT_ALGO}" rounds="${4:-$DEFAULT_ROUNDS}" salt="$5"
    echo -n "$value" | openssl enc -"$algo" -pbkdf2 -iter "$rounds" -nosalt -S "$salt" -pass "pass:$passphrase" -base64 2>/dev/null
}

decrypt_value() {
    local encrypted="$1" passphrase="$2" algo="${3:-$DEFAULT_ALGO}" rounds="${4:-$DEFAULT_ROUNDS}" salt="${5:-}"
    if [ -n "$salt" ]; then
        echo "$encrypted" | openssl enc -d -"$algo" -pbkdf2 -iter "$rounds" -nosalt -S "$salt" -pass "pass:$passphrase" -base64 2>/dev/null
    else
        # Backward compatibility: v1 secrets use embedded salt
        echo "$encrypted" | openssl enc -d -"$algo" -pbkdf2 -iter "$rounds" -pass "pass:$passphrase" -base64 2>/dev/null
    fi
}

wrap_secret() {
    local value="$1" algo="${2:-}" rounds="${3:-}" key_algo="${4:-}" salt="${5:-}"
    if [ -n "$algo" ]; then
        jq -nc --arg v "$value" --arg a "$algo" --argjson r "$rounds" \
            --arg k "$key_algo" --arg salt "$salt" --arg s "$SCHEMA" \
            '{schema: $s, value: $v, algo: $a, rounds: $r, keyAlgo: $k, salt: $salt}'
    else
        jq -nc --arg v "$value" --arg s "$SCHEMA" \
            '{schema: $s, value: $v, algo: null, rounds: null, keyAlgo: null, salt: null}'
    fi
}

unwrap_secret() {
    local raw="$1"

    if ! echo "$raw" | jq -e . >/dev/null 2>&1; then
        echo "$raw"
        return 0
    fi

    if ! is_wrapped_secret "$raw"; then
        echo "$raw"
        return 0
    fi

    if ! validate_secret "$raw"; then
        return 1
    fi

    local algo value rounds key_algo salt
    algo=$(echo "$raw" | jq -r '.algo // empty')
    value=$(echo "$raw" | jq -r '.value')
    rounds=$(echo "$raw" | jq -r '.rounds // empty')
    key_algo=$(echo "$raw" | jq -r '.keyAlgo // empty')
    salt=$(echo "$raw" | jq -r '.salt // empty')

    # Backward compatibility: v1 secrets don't have keyAlgo, default to pbkdf2
    [ -z "$key_algo" ] && key_algo="pbkdf2"

    if [ -z "$algo" ]; then
        echo "$value"
        return 0
    fi

    if [ "$key_algo" != "pbkdf2" ]; then
        echo "Error: Unsupported key derivation algorithm: $key_algo" >&2
        return 1
    fi

    local passphrase decrypted
    passphrase=$(prompt_passphrase "Enter decryption passphrase") || return 1

    decrypted=$(decrypt_value "$value" "$passphrase" "$algo" "$rounds" "$salt")
    if [ -z "$decrypted" ]; then
        echo "Error: Decryption failed - incorrect passphrase or corrupted data" >&2
        return 1
    fi
    echo "$decrypted"
}

get_local() {
    local name="$1" service="$2" account="$3" pass_path="$4" check_env="$5" required="$6"

    if [ "$check_env" = true ]; then
        local env_val
        env_val=$(printenv "$name" 2>/dev/null || true)
        if [ -n "$env_val" ]; then
            echo "$env_val"
            return 0
        fi
    fi

    if [[ "$(uname)" == "Darwin" ]]; then
        if security find-generic-password -w -s "$service" -a "$account" 2>/dev/null; then
            return 0
        elif security find-generic-password -w -s "$name" -a "$account" 2>/dev/null; then
            return 0
        elif [ "$required" = true ]; then
            echo "Error: $name not found in macOS Keychain" >&2
            return 1
        fi
    else
        if pass show "$pass_path" 2>/dev/null; then
            return 0
        elif pass show "$name" 2>/dev/null; then
            return 0
        elif [ "$required" = true ]; then
            echo "Error: $name not found in pass" >&2
            return 1
        fi
    fi
}

get_network() {
    local name="$1" project="$2" required="$3"
    check_gcloud_auth
    if gcloud secrets versions access latest --secret="$name" --project="$project" 2>/dev/null; then
        return 0
    elif [ "$required" = true ]; then
        echo "Error: $name not found in GCP Secret Manager (project: $project)" >&2
        return 1
    fi
}

store_local() {
    local name="$1" value="$2" service="$3" account="$4" pass_path="$5"

    if [[ "$(uname)" == "Darwin" ]]; then
        security delete-generic-password -s "$service" -a "$account" &>/dev/null || true
        if security add-generic-password -s "$service" -a "$account" -w "$value" &>/dev/null; then
            debug_msg "Secret stored in macOS Keychain"
            return 0
        else
            echo "Error: Failed to store secret in macOS Keychain" >&2
            return 1
        fi
    else
        if echo "$value" | pass insert -e "$pass_path" &>/dev/null; then
            debug_msg "Secret stored in pass"
            return 0
        else
            echo "Error: Failed to store secret in pass" >&2
            return 1
        fi
    fi
}

store_network() {
    local name="$1" value="$2" project="$3"
    check_gcloud_auth

    if gcloud secrets describe "$name" --project="$project" &>/dev/null; then
        if echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --project="$project" >/dev/null; then
            debug_msg "Secret updated in GCP Secret Manager"
            return 0
        fi
    else
        if echo -n "$value" | gcloud secrets create "$name" --data-file=- --project="$project" >/dev/null; then
            debug_msg "Secret created in GCP Secret Manager"
            return 0
        fi
    fi
    echo "Error: Failed to store secret in GCP Secret Manager" >&2
    return 1
}

list_local() {
    if [[ "$(uname)" == "Darwin" ]]; then
        security dump-keychain 2>/dev/null | grep '"svce"<blob>="'"$PREFIX"'/' | sed -n 's/.*"svce"<blob>="\([^"]*\)".*/\1/p' | sed "s|^$PREFIX/||" || true
    else
        pass ls "$PREFIX" 2>/dev/null | tail -n +2 | sed 's/^[^a-zA-Z]*//' || true
    fi
}

list_network() {
    local project="$1"
    check_gcloud_auth
    gcloud secrets list --project="$project" --format='value(name)' 2>/dev/null || true
}

delete_local() {
    local name="$1" service="$2" account="$3" pass_path="$4"

    if [[ "$(uname)" == "Darwin" ]]; then
        if security delete-generic-password -s "$service" -a "$account" &>/dev/null; then
            debug_msg "Secret deleted from macOS Keychain"
            return 0
        elif security delete-generic-password -s "$name" -a "$account" &>/dev/null; then
            debug_msg "Secret deleted from macOS Keychain"
            return 0
        else
            echo "Error: $name not found in macOS Keychain" >&2
            return 1
        fi
    else
        if pass rm -f "$pass_path" 2>/dev/null; then
            debug_msg "Secret deleted from pass"
            return 0
        elif pass rm -f "$name" 2>/dev/null; then
            debug_msg "Secret deleted from pass"
            return 0
        else
            echo "Error: $name not found in pass" >&2
            return 1
        fi
    fi
}

delete_network() {
    local name="$1" project="$2"
    check_gcloud_auth
    if gcloud secrets delete "$name" --project="$project" --quiet 2>/dev/null; then
        debug_msg "Secret deleted from GCP Secret Manager"
        return 0
    else
        echo "Error: $name not found in GCP Secret Manager (project: $project)" >&2
        return 1
    fi
}

parse_global_opts() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-dir)
                SECRETSLIB_DIR="$2"
                MASTER_KEY_FILE="$SECRETSLIB_DIR/master-key"
                HISTORY_FILE="$SECRETSLIB_DIR/history.jsonl"
                shift 2
                ;;
            --passphrase)
                TEST_PASSPHRASE="$2"
                shift 2
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --sqlite)
                SQLITE_DB="$2"
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

REMAINING_ARGS=()
parse_global_opts "$@"
set -- "${REMAINING_ARGS[@]}"

if [[ $# -eq 0 ]]; then
    usage >&2
    exit 1
fi

ensure_secretslib

COMMAND="$1"
shift

case "$COMMAND" in
    get)
        NAME=""
        if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
            NAME="$1"
            shift
        fi
        SERVICE="$PREFIX/$NAME"
        ACCOUNT="$USER"
        PASS_PATH="$PREFIX/$NAME"
        PROJECT="${GOOGLE_CLOUD_PROJECT:-modiase-infra}"
        CHECK_ENV=true
        REQUIRED=true
        BACKEND="local"
        ALL=false
        FORCE_PRINT=false
        RAW=false

        [ -n "$SQLITE_DB" ] && BACKEND="sqlite" || true

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --account)
                    ACCOUNT="$2"
                    shift 2
                    ;;
                --all)
                    ALL=true
                    shift
                    ;;
                --local)
                    BACKEND="local"
                    shift
                    ;;
                --network)
                    BACKEND="network"
                    shift
                    ;;
                --no-env)
                    CHECK_ENV=false
                    shift
                    ;;
                --optional)
                    REQUIRED=false
                    shift
                    ;;
                --pass-path)
                    PASS_PATH="$2"
                    shift 2
                    ;;
                --print)
                    FORCE_PRINT=true
                    shift
                    ;;
                --project)
                    PROJECT="$2"
                    shift 2
                    ;;
                --raw)
                    RAW=true
                    shift
                    ;;
                --service)
                    SERVICE="$2"
                    shift 2
                    ;;
                --sqlite)
                    SQLITE_DB="$2"
                    BACKEND="sqlite"
                    shift 2
                    ;;
                --data-dir | --passphrase | --force)
                    shift
                    [ "$1" != "" ] && [[ ! "$1" =~ ^- ]] && shift || true
                    ;;
                -h | --help)
                    usage
                    exit 0
                    ;;
                *)
                    echo "Unknown option: $1" >&2
                    usage
                    exit 1
                    ;;
            esac
        done

        if [ -z "$NAME" ]; then
            if [ "$BACKEND" = "sqlite" ]; then
                NAME=$(list_sqlite "$SQLITE_DB" | gum choose)
            elif [ "$ALL" = true ]; then
                NAME=$({
                    list_local
                    list_network "$PROJECT"
                } | sort | gum choose)
            elif [ "$BACKEND" = "network" ]; then
                NAME=$(list_network "$PROJECT" | gum choose)
            else
                NAME=$(list_local | gum choose)
            fi
            if [ -z "$NAME" ]; then exit 1; fi
            SERVICE="$PREFIX/$NAME"
            PASS_PATH="$PREFIX/$NAME"
        fi

        if [ "$BACKEND" = "sqlite" ]; then
            SECRET=$(get_sqlite "$NAME" "$SQLITE_DB")
            if [ -z "$SECRET" ] && [ "$REQUIRED" = true ]; then
                echo "Error: $NAME not found in SQLite database" >&2
                exit 1
            fi
        elif [ "$ALL" = true ]; then
            SECRET=$(get_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" "$CHECK_ENV" false)
            [ -z "$SECRET" ] && SECRET=$(get_network "$NAME" "$PROJECT" "$REQUIRED") || true
        elif [ "$BACKEND" = "network" ]; then
            SECRET=$(get_network "$NAME" "$PROJECT" "$REQUIRED")
        else
            SECRET=$(get_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" "$CHECK_ENV" "$REQUIRED")
        fi

        if [ -n "$SECRET" ]; then
            if [ "$RAW" = false ]; then
                SECRET=$(unwrap_secret "$SECRET") || exit 1
            fi
            log_operation "get" "$NAME" "$BACKEND"

            if [ "$FORCE_PRINT" = true ] || [ ! -t 1 ]; then
                echo "$SECRET"
            else
                echo -n "$SECRET" | copy_to_clipboard
                echo "Copied $NAME to clipboard" >&2
            fi
        fi
        ;;

    store)
        if [[ $# -eq 0 ]]; then
            echo "Error: NAME required for store command" >&2
            usage
            exit 1
        fi
        NAME="$1"
        shift
        VALUE=""
        SERVICE="$PREFIX/$NAME"
        ACCOUNT="$USER"
        PASS_PATH="$PREFIX/$NAME"
        PROJECT="${GOOGLE_CLOUD_PROJECT:-modiase-infra}"
        BACKEND="local"
        ENCRYPT=false
        ALGO=""
        ROUNDS=""

        [ -n "$SQLITE_DB" ] && BACKEND="sqlite" || true

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --account)
                    ACCOUNT="$2"
                    shift 2
                    ;;
                --algo)
                    ALGO="$2"
                    shift 2
                    ;;
                --key)
                    ENCRYPT=true
                    shift
                    ;;
                --local)
                    BACKEND="local"
                    shift
                    ;;
                --network)
                    BACKEND="network"
                    shift
                    ;;
                --pass-path)
                    PASS_PATH="$2"
                    shift 2
                    ;;
                --project)
                    PROJECT="$2"
                    shift 2
                    ;;
                --rounds)
                    ROUNDS="$2"
                    shift 2
                    ;;
                --service)
                    SERVICE="$2"
                    shift 2
                    ;;
                --sqlite)
                    SQLITE_DB="$2"
                    BACKEND="sqlite"
                    shift 2
                    ;;
                --data-dir | --passphrase | --force)
                    shift
                    [ "$1" != "" ] && [[ ! "$1" =~ ^- ]] && shift || true
                    ;;
                -h | --help)
                    usage
                    exit 0
                    ;;
                -*)
                    echo "Unknown option: $1" >&2
                    usage
                    exit 1
                    ;;
                *)
                    if [ -z "$VALUE" ]; then
                        VALUE="$1"
                        shift
                    else
                        echo "Unknown option: $1" >&2
                        usage
                        exit 1
                    fi
                    ;;
            esac
        done

        if [ "$ENCRYPT" = false ]; then
            [ -n "$ROUNDS" ] && echo "Warning: --rounds ignored without --key" >&2 || true
            [ -n "$ALGO" ] && echo "Warning: --algo ignored without --key" >&2 || true
        fi

        [ -z "$ALGO" ] && ALGO="$DEFAULT_ALGO" || true
        [ -z "$ROUNDS" ] && ROUNDS="$DEFAULT_ROUNDS" || true

        if [ "$ENCRYPT" = true ] && [ "$ALGO" != "aes-256-cbc" ]; then
            echo "Error: Only aes-256-cbc algorithm is supported" >&2
            exit 1
        fi

        if [ -z "$VALUE" ]; then
            if [ -n "$TEST_PASSPHRASE" ]; then
                echo "Error: No value provided" >&2
                exit 1
            fi
            VALUE=$(gum input --password --placeholder "Enter secret value for $NAME...")
            if [ -z "$VALUE" ]; then
                echo "Error: No value provided" >&2
                exit 1
            fi
        fi

        EXISTING=""
        if [ "$BACKEND" = "sqlite" ]; then
            EXISTING=$(get_sqlite "$NAME" "$SQLITE_DB" 2>/dev/null || true)
        elif [ "$BACKEND" = "network" ]; then
            EXISTING=$(get_network "$NAME" "$PROJECT" false 2>/dev/null || true)
        else
            EXISTING=$(get_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" false false 2>/dev/null || true)
        fi

        if [ -n "$EXISTING" ] && [ "$FORCE" != true ]; then
            if [ ! -t 0 ]; then
                echo "Error: Secret '$NAME' already exists (use --force to overwrite)" >&2
                exit 1
            fi
            if ! gum confirm "Secret '$NAME' already exists. Overwrite?"; then
                echo "Cancelled" >&2
                exit 1
            fi
        fi

        if [ "$ENCRYPT" = true ]; then
            PASSPHRASE=$(prompt_passphrase "Enter encryption passphrase") || exit 1

            if [ -z "$TEST_PASSPHRASE" ]; then
                PASSPHRASE_CONFIRM=$(prompt_passphrase "Confirm passphrase") || exit 1
                if [ "$PASSPHRASE" != "$PASSPHRASE_CONFIRM" ]; then
                    echo "Error: Passphrases do not match" >&2
                    exit 1
                fi
            fi

            SALT=$(generate_salt)
            ENCRYPTED=$(encrypt_value "$VALUE" "$PASSPHRASE" "$ALGO" "$ROUNDS" "$SALT")
            if [ -z "$ENCRYPTED" ]; then
                echo "Error: Encryption failed" >&2
                exit 1
            fi

            WRAPPED=$(wrap_secret "$ENCRYPTED" "$ALGO" "$ROUNDS" "$DEFAULT_KEY_ALGO" "$SALT")
        else
            WRAPPED=$(wrap_secret "$VALUE")
        fi

        if [ "$BACKEND" = "sqlite" ]; then
            store_sqlite "$NAME" "$WRAPPED" "$SQLITE_DB" && log_operation "store" "$NAME" "$BACKEND"
        elif [ "$BACKEND" = "network" ]; then
            store_network "$NAME" "$WRAPPED" "$PROJECT" && log_operation "store" "$NAME" "$BACKEND"
        else
            store_local "$NAME" "$WRAPPED" "$SERVICE" "$ACCOUNT" "$PASS_PATH" && log_operation "store" "$NAME" "$BACKEND"
        fi
        ;;

    list)
        PROJECT="${GOOGLE_CLOUD_PROJECT:-modiase-infra}"
        BACKEND="local"
        ALL=false

        [ -n "$SQLITE_DB" ] && BACKEND="sqlite" || true

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --all)
                    ALL=true
                    shift
                    ;;
                --local)
                    BACKEND="local"
                    shift
                    ;;
                --network)
                    BACKEND="network"
                    shift
                    ;;
                --project)
                    PROJECT="$2"
                    shift 2
                    ;;
                --sqlite)
                    SQLITE_DB="$2"
                    BACKEND="sqlite"
                    shift 2
                    ;;
                --data-dir | --passphrase | --force)
                    shift
                    [ "$1" != "" ] && [[ ! "$1" =~ ^- ]] && shift || true
                    ;;
                -h | --help)
                    usage
                    exit 0
                    ;;
                *)
                    echo "Unknown option: $1" >&2
                    usage
                    exit 1
                    ;;
            esac
        done

        log_operation "list" "-" "$BACKEND"
        if [ "$BACKEND" = "sqlite" ]; then
            list_sqlite "$SQLITE_DB" | less -F
        elif [ "$ALL" = true ]; then
            {
                list_local
                list_network "$PROJECT"
            } | sort | less -F
        elif [ "$BACKEND" = "network" ]; then
            list_network "$PROJECT" | less -F
        else
            list_local | less -F
        fi
        ;;

    delete)
        if [[ $# -eq 0 ]]; then
            echo "Error: NAME or 'undo' required for delete command" >&2
            usage
            exit 1
        fi

        if [ "$1" = "undo" ]; then
            LAST_DELETE=$(grep '"op":"delete"' "$HISTORY_FILE" 2>/dev/null | tail -1 || true)
            if [ -z "$LAST_DELETE" ]; then
                echo "Error: No delete operations to undo" >&2
                exit 1
            fi

            NAME=$(echo "$LAST_DELETE" | jq -r '.name')
            BACKEND=$(echo "$LAST_DELETE" | jq -r '.backend')
            BACKUP=$(echo "$LAST_DELETE" | jq -r '.backup')

            RESTORED=$(decrypt_with_master "$BACKUP")
            if [ -z "$RESTORED" ]; then
                echo "Error: Failed to decrypt backup" >&2
                exit 1
            fi

            SERVICE="$PREFIX/$NAME"
            ACCOUNT="$USER"
            PASS_PATH="$PREFIX/$NAME"
            PROJECT="${GOOGLE_CLOUD_PROJECT:-modiase-infra}"

            if [ "$BACKEND" = "sqlite" ]; then
                store_sqlite "$NAME" "$RESTORED" "$SQLITE_DB"
            elif [ "$BACKEND" = "network" ]; then
                store_network "$NAME" "$RESTORED" "$PROJECT"
            else
                store_local "$NAME" "$RESTORED" "$SERVICE" "$ACCOUNT" "$PASS_PATH"
            fi

            log_operation "undo" "$NAME" "$BACKEND"
            echo "Restored $NAME from backup" >&2
            exit 0
        fi

        NAME="$1"
        shift
        SERVICE="$PREFIX/$NAME"
        ACCOUNT="$USER"
        PASS_PATH="$PREFIX/$NAME"
        PROJECT="${GOOGLE_CLOUD_PROJECT:-modiase-infra}"
        BACKEND="local"

        [ -n "$SQLITE_DB" ] && BACKEND="sqlite" || true

        while [[ $# -gt 0 ]]; do
            case "$1" in
                --account)
                    ACCOUNT="$2"
                    shift 2
                    ;;
                --local)
                    BACKEND="local"
                    shift
                    ;;
                --network)
                    BACKEND="network"
                    shift
                    ;;
                --pass-path)
                    PASS_PATH="$2"
                    shift 2
                    ;;
                --project)
                    PROJECT="$2"
                    shift 2
                    ;;
                --service)
                    SERVICE="$2"
                    shift 2
                    ;;
                --sqlite)
                    SQLITE_DB="$2"
                    BACKEND="sqlite"
                    shift 2
                    ;;
                --data-dir | --passphrase | --force)
                    shift
                    [ "$1" != "" ] && [[ ! "$1" =~ ^- ]] && shift || true
                    ;;
                -h | --help)
                    usage
                    exit 0
                    ;;
                *)
                    echo "Unknown option: $1" >&2
                    usage
                    exit 1
                    ;;
            esac
        done

        if [ "$FORCE" != true ]; then
            if ! gum confirm "Delete secret '$NAME' from $BACKEND?"; then
                echo "Cancelled" >&2
                exit 1
            fi
        fi

        if [ "$BACKEND" = "sqlite" ]; then
            CURRENT=$(get_sqlite "$NAME" "$SQLITE_DB")
        elif [ "$BACKEND" = "network" ]; then
            CURRENT=$(get_network "$NAME" "$PROJECT" false)
        else
            CURRENT=$(get_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" false false)
        fi

        if [ -n "$CURRENT" ]; then
            BACKUP=$(encrypt_with_master "$CURRENT")
        else
            BACKUP=""
        fi

        if [ "$BACKEND" = "sqlite" ]; then
            delete_sqlite "$NAME" "$SQLITE_DB" && log_operation "delete" "$NAME" "$BACKEND" "$BACKUP"
        elif [ "$BACKEND" = "network" ]; then
            delete_network "$NAME" "$PROJECT" && log_operation "delete" "$NAME" "$BACKEND" "$BACKUP"
        else
            delete_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" && log_operation "delete" "$NAME" "$BACKEND" "$BACKUP"
        fi
        ;;

    log)
        if [ ! -s "$HISTORY_FILE" ]; then
            echo "No operations logged yet" >&2
            exit 0
        fi

        while IFS= read -r line; do
            op=$(echo "$line" | jq -r '.op')
            ts=$(echo "$line" | jq -r '.ts')
            name=$(echo "$line" | jq -r '.name')
            backend=$(echo "$line" | jq -r '.backend')

            case "$op" in
                get | list) colour="$GREEN" ;;
                store) colour="$YELLOW" ;;
                delete) colour="$RED" ;;
                undo) colour="$CYAN" ;;
                *) colour="$NC" ;;
            esac

            printf "%b%-8s%b %s  %-20s  [%s]\n" "$colour" "$op" "$NC" "$ts" "$name" "$backend"
        done <"$HISTORY_FILE" | less -R -F
        ;;

    -h | --help)
        usage
        exit 0
        ;;

    *)
        echo "Unknown command: $COMMAND" >&2
        usage
        exit 1
        ;;
esac
