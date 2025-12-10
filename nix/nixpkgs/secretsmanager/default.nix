{
  writeShellApplication,
  coreutils,
  pass,
  stdenv,
  lib,
}:

writeShellApplication {
  name = "secretsmanager";
  runtimeInputs = [ coreutils ] ++ lib.optionals stdenv.isLinux [ pass ];
  text = ''
        usage() {
          cat <<'EOF'
    Usage: secretsmanager <command> [OPTIONS]

    Commands:
      get NAME [OPTIONS]           Retrieve a secret
      store NAME VALUE [OPTIONS]   Store a secret

    Get Options:
      --service SERVICE     Keychain service name (default: NAME)
      --account ACCOUNT     Keychain account (default: $USER)
      --pass-path PATH      Pass entry path (default: NAME)
      --no-env              Skip environment variable check
      --optional            Don't error if secret not found
      -h, --help            Show this help

    Store Options:
      --service SERVICE     Keychain service name (default: NAME)
      --account ACCOUNT     Keychain account (default: $USER)
      --pass-path PATH      Pass entry path (default: NAME)
      -h, --help            Show this help

    Examples:
      secretsmanager get GEMINI_API_KEY
      secretsmanager get ANTHROPIC_API_KEY --pass-path anthropic-api-key
      secretsmanager store GEMINI_API_KEY "your-api-key-here"
      secretsmanager store ANTHROPIC_API_KEY "key" --pass-path anthropic-api-key
    EOF
        }

        if [[ $# -eq 0 ]]; then
          usage
          exit 1
        fi

        COMMAND="$1"
        shift

        case "$COMMAND" in
          get)
            if [[ $# -eq 0 ]]; then
              echo "Error: NAME required for get command" >&2
              usage
              exit 1
            fi

            NAME="$1"
            shift

            SERVICE="$NAME"
            ACCOUNT="$USER"
            PASS_PATH="$NAME"
            CHECK_ENV=true
            REQUIRED=true

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --service)
                  SERVICE="$2"
                  shift 2
                  ;;
                --account)
                  ACCOUNT="$2"
                  shift 2
                  ;;
                --pass-path)
                  PASS_PATH="$2"
                  shift 2
                  ;;
                --no-env)
                  CHECK_ENV=false
                  shift
                  ;;
                --optional)
                  REQUIRED=false
                  shift
                  ;;
                -h|--help)
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

            if [ "$CHECK_ENV" = true ] && [ -n "''${!NAME:-}" ]; then
              echo "''${!NAME}"
              exit 0
            fi

            if [[ "$(uname)" == "Darwin" ]]; then
              if security find-generic-password -w -s "$SERVICE" -a "$ACCOUNT" 2>/dev/null; then
                exit 0
              else
                if [ "$REQUIRED" = true ]; then
                  echo "Error: $NAME not found in macOS Keychain (service: $SERVICE, account: $ACCOUNT)" >&2
                  exit 1
                else
                  exit 0
                fi
              fi
            else
              if pass show "$PASS_PATH" 2>/dev/null; then
                exit 0
              else
                if [ "$REQUIRED" = true ]; then
                  echo "Error: $NAME not found in pass (path: $PASS_PATH)" >&2
                  exit 1
                else
                  exit 0
                fi
              fi
            fi
            ;;

          store)
            if [[ $# -lt 2 ]]; then
              echo "Error: NAME and VALUE required for store command" >&2
              usage
              exit 1
            fi

            NAME="$1"
            VALUE="$2"
            shift 2

            SERVICE="$NAME"
            ACCOUNT="$USER"
            PASS_PATH="$NAME"

            while [[ $# -gt 0 ]]; do
              case "$1" in
                --service)
                  SERVICE="$2"
                  shift 2
                  ;;
                --account)
                  ACCOUNT="$2"
                  shift 2
                  ;;
                --pass-path)
                  PASS_PATH="$2"
                  shift 2
                  ;;
                -h|--help)
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

            if [[ "$(uname)" == "Darwin" ]]; then
              security delete-generic-password -s "$SERVICE" -a "$ACCOUNT" 2>/dev/null || true
              if security add-generic-password -s "$SERVICE" -a "$ACCOUNT" -w "$VALUE"; then
                echo "Secret stored successfully in macOS Keychain" >&2
                exit 0
              else
                echo "Error: Failed to store secret in macOS Keychain" >&2
                exit 1
              fi
            else
              if echo "$VALUE" | pass insert -e "$PASS_PATH"; then
                echo "Secret stored successfully in pass" >&2
                exit 0
              else
                echo "Error: Failed to store secret in pass" >&2
                exit 1
              fi
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
