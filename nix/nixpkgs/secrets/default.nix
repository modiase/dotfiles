{
  writeShellApplication,
  coreutils,
  google-cloud-sdk,
  pass,
  stdenv,
  lib,
}:

writeShellApplication {
  name = "secrets";
  runtimeInputs = [
    coreutils
    google-cloud-sdk
  ]
  ++ lib.optionals stdenv.isLinux [ pass ];
  text = ''
        PREFIX="secrets"

        usage() {
          cat <<'EOF'
    Usage: secrets <command> [OPTIONS]

    A unified frontend for secrets management across platforms.
      - macOS: Uses Keychain via 'security' command (stored as secrets/NAME)
      - Linux: Uses 'pass' password store (stored as secrets/NAME)
      - Network: Uses Google Cloud Secret Manager (--network, requires gcloud auth)

    Commands:
      get NAME [OPTIONS]           Retrieve a secret
      store NAME VALUE [OPTIONS]   Store a secret
      list [OPTIONS]               List available secrets

    Backend Flags:
      --local                 Use local backend (default)
      --network               Use Google Cloud Secret Manager

    Get/Store Options:
      --service SERVICE       Keychain service name (default: secrets/NAME)
      --account ACCOUNT       Keychain account (default: $USER)
      --pass-path PATH        Pass entry path (default: secrets/NAME)
      --project PROJECT       GCP project for --network (default: $GOOGLE_CLOUD_PROJECT)
      --no-env                Skip environment variable check
      --optional              Don't error if secret not found
      -h, --help              Show this help

    Examples:
      secrets get GEMINI_API_KEY                         # Local (keychain/pass)
      secrets get ANTHROPIC_API_KEY --network            # From GCP Secret Manager
      secrets store GEMINI_API_KEY "your-api-key"        # Store locally
      secrets store API_KEY "value" --network            # Store in GCP
      secrets list                                       # List local secrets
      secrets list --network --project my-project        # List GCP secrets
    EOF
        }

        check_gcloud_auth() {
          if ! gcloud auth print-access-token &>/dev/null; then
            echo "Error: Not authenticated with gcloud. Run 'gcloud auth login' first." >&2
            exit 1
          fi
        }

        get_local() {
          local name="$1" service="$2" account="$3" pass_path="$4" check_env="$5" required="$6"

          if [ "$check_env" = true ] && [ -n "''${!name:-}" ]; then
            echo "''${!name}"
            return 0
          fi

          if [[ "$(uname)" == "Darwin" ]]; then
            if security find-generic-password -w -s "$service" -a "$account" 2>/dev/null; then
              return 0
            elif security find-generic-password -w -s "$name" -a "$account" 2>/dev/null; then
              return 0
            else
              [ "$required" = true ] && echo "Error: $name not found in macOS Keychain" >&2 && return 1
              return 0
            fi
          else
            if pass show "$pass_path" 2>/dev/null; then
              return 0
            elif pass show "$name" 2>/dev/null; then
              return 0
            else
              [ "$required" = true ] && echo "Error: $name not found in pass" >&2 && return 1
              return 0
            fi
          fi
        }

        get_network() {
          local name="$1" project="$2" required="$3"
          check_gcloud_auth
          if gcloud secrets versions access latest --secret="$name" --project="$project" 2>/dev/null; then
            return 0
          else
            [ "$required" = true ] && echo "Error: $name not found in GCP Secret Manager (project: $project)" >&2 && return 1
            return 0
          fi
        }

        store_local() {
          local name="$1" value="$2" service="$3" account="$4" pass_path="$5"

          if [[ "$(uname)" == "Darwin" ]]; then
            security delete-generic-password -s "$service" -a "$account" 2>/dev/null || true
            if security add-generic-password -s "$service" -a "$account" -w "$value"; then
              echo "Secret stored in macOS Keychain" >&2
              return 0
            else
              echo "Error: Failed to store secret in macOS Keychain" >&2
              return 1
            fi
          else
            if echo "$value" | pass insert -e "$pass_path"; then
              echo "Secret stored in pass" >&2
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
            if echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --project="$project"; then
              echo "Secret updated in GCP Secret Manager" >&2
              return 0
            fi
          else
            if echo -n "$value" | gcloud secrets create "$name" --data-file=- --project="$project"; then
              echo "Secret created in GCP Secret Manager" >&2
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

        if [[ $# -eq 0 ]]; then usage; exit 1; fi

        COMMAND="$1"
        shift

        case "$COMMAND" in
          get)
            if [[ $# -eq 0 ]]; then echo "Error: NAME required for get command" >&2; usage; exit 1; fi
            NAME="$1"; shift
            SERVICE="$PREFIX/$NAME"
            ACCOUNT="$USER"
            PASS_PATH="$PREFIX/$NAME"
            PROJECT="''${GOOGLE_CLOUD_PROJECT:-}"
            CHECK_ENV=true
            REQUIRED=true
            BACKEND="local"

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --local) BACKEND="local"; shift ;;
                --network) BACKEND="network"; shift ;;
                --service) SERVICE="$2"; shift 2 ;;
                --account) ACCOUNT="$2"; shift 2 ;;
                --pass-path) PASS_PATH="$2"; shift 2 ;;
                --project) PROJECT="$2"; shift 2 ;;
                --no-env) CHECK_ENV=false; shift ;;
                --optional) REQUIRED=false; shift ;;
                -h|--help) usage; exit 0 ;;
                *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
              esac
            done

            if [ "$BACKEND" = "network" ]; then
              [ -z "$PROJECT" ] && { echo "Error: --project or GOOGLE_CLOUD_PROJECT required for --network" >&2; exit 1; }
              get_network "$NAME" "$PROJECT" "$REQUIRED"
            else
              get_local "$NAME" "$SERVICE" "$ACCOUNT" "$PASS_PATH" "$CHECK_ENV" "$REQUIRED"
            fi
            ;;

          store)
            if [[ $# -lt 2 ]]; then echo "Error: NAME and VALUE required for store command" >&2; usage; exit 1; fi
            NAME="$1"; VALUE="$2"; shift 2
            SERVICE="$PREFIX/$NAME"
            ACCOUNT="$USER"
            PASS_PATH="$PREFIX/$NAME"
            PROJECT="''${GOOGLE_CLOUD_PROJECT:-}"
            BACKEND="local"

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --local) BACKEND="local"; shift ;;
                --network) BACKEND="network"; shift ;;
                --service) SERVICE="$2"; shift 2 ;;
                --account) ACCOUNT="$2"; shift 2 ;;
                --pass-path) PASS_PATH="$2"; shift 2 ;;
                --project) PROJECT="$2"; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
              esac
            done

            if [ "$BACKEND" = "network" ]; then
              [ -z "$PROJECT" ] && { echo "Error: --project or GOOGLE_CLOUD_PROJECT required for --network" >&2; exit 1; }
              store_network "$NAME" "$VALUE" "$PROJECT"
            else
              store_local "$NAME" "$VALUE" "$SERVICE" "$ACCOUNT" "$PASS_PATH"
            fi
            ;;

          list)
            PROJECT="''${GOOGLE_CLOUD_PROJECT:-}"
            BACKEND="local"

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --local) BACKEND="local"; shift ;;
                --network) BACKEND="network"; shift ;;
                --project) PROJECT="$2"; shift 2 ;;
                -h|--help) usage; exit 0 ;;
                *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
              esac
            done

            if [ "$BACKEND" = "network" ]; then
              [ -z "$PROJECT" ] && { echo "Error: --project or GOOGLE_CLOUD_PROJECT required for --network" >&2; exit 1; }
              list_network "$PROJECT"
            else
              list_local
            fi
            ;;

          -h|--help)
            usage
            exit 0
            ;;

          *)
            echo "Unknown command: $COMMAND" >&2
            usage
            exit 1
            ;;
        esac
  '';
}
