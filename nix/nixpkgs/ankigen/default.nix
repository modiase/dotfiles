{ pkgs, lib, ... }:

let
  secretsmanager = pkgs.callPackage ../secretsmanager { };
in
pkgs.writeShellScriptBin "ankigen" ''
  set -euo pipefail

  DEBUG=0
  NO_CACHE=false
  USE_WEB=false
  FAST=false
  TOKENS=2000
  FORMAT=true

  get_system_prompt() {
    local url="https://gist.githubusercontent.com/modiase/88cbb2e7947a4ae970a91d9e335ab59c/raw/anki.txt"
    [ "$NO_CACHE" = true ] && url="$url?t=$(date +%s)"
    ${pkgs.httpie}/bin/http --body GET "$url"
  }

  ensure_request_success() {
    local status="$1"
    local body="$2"

    if [ "$status" -ne 0 ]; then
      echo -e "\033[0;31mHTTP request failed with status $status:\033[0m" >&2
      echo -e "\033[0;31m$body\033[0m" >&2
      return 1
    fi

    local api_error
    api_error=$(printf '%s' "$body" | ${pkgs.jq}/bin/jq -r '.error // empty')
    if [ -n "$api_error" ]; then
      echo -e "\033[0;31mAPI Error:\033[0m" >&2
      echo -e "\033[0;31m$body\033[0m" >&2
      return 1
    fi
  }

  build_user_message() {
    printf 'Please create an Anki card for the following question: %s' "$1"
  }

  format_cards() {
    local input="$1"
    local front back

    front=$(echo "$input" | ${pkgs.gnused}/bin/sed -n 's|.*<front>\(.*\)</front>.*|\1|p')
    back=$(echo "$input" | ${pkgs.gnused}/bin/sed -n 's|.*<back>\(.*\)</back>.*|\1|p')

    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ FRONT                                                           │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo "$front"
    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"
    echo "│ BACK                                                            │"
    echo "└─────────────────────────────────────────────────────────────────┘"
    echo "$back"
    echo ""
    echo "═════════════════════════════════════════════════════════════════"
  }

  ankigen_claude() {
    local api_key
    if ! api_key="$(${secretsmanager}/bin/secretsmanager get ANTHROPIC_API_KEY --pass-path anthropic-api-key)"; then
      exit 1
    fi
    local user_message
    user_message=$(build_user_message "$1")
    local model="claude-opus-4-5-20251101"
    [ "$FAST" = true ] && model="claude-haiku-4-5-20251001"

    local tools='[]'
    [ "$USE_WEB" = true ] && tools='[{"type": "web_search_20250305", "name": "web_search", "max_uses": 5}]'

    local request=$(${pkgs.jq}/bin/jq -n \
      --arg system "$(get_system_prompt)" \
      --arg user_message "$user_message" \
      --arg model "$model" \
      --argjson tokens "$TOKENS" \
      --argjson tools "$tools" \
      '{model: $model, max_tokens: $tokens, temperature: 0.3, system: $system, messages: [{role: "user", content: $user_message}], tools: $tools}')

    local raw_response
    raw_response=$(echo "$request" | ${pkgs.httpie}/bin/http POST https://api.anthropic.com/v1/messages \
        "x-api-key:$api_key" \
        "anthropic-version:2023-06-01" \
        "Content-Type:application/json" \
        "strip-tm:true")
    local http_status=$?

    if ! ensure_request_success "$http_status" "$raw_response"; then
      exit 1
    fi

    local output
    output=$(echo "$raw_response" | ${pkgs.jq}/bin/jq -r '.content[0].text' | ${pkgs.gnused}/bin/sed -e '/<thinking>/,/<\/thinking>/d' -e '/<drafts>/,/<\/drafts>/d')

    if [ "$FORMAT" = true ]; then
      format_cards "$output"
    else
      echo "$output"
    fi
  }

  ankigen_chatgpt() {
    local api_key
    if ! api_key="$(${secretsmanager}/bin/secretsmanager get OPENAI_API_KEY --pass-path openai-api-key)"; then
      exit 1
    fi
    local user_message
    user_message=$(build_user_message "$1")

    local model="gpt-4.1-2025-04-14"
    [ "$FAST" = true ] && model="o4-mini-2025-04-16"

    local tools='[]'
    [ "$USE_WEB" = true ] && tools='[{"type":"web_search"}]'

    local request=$(${pkgs.jq}/bin/jq -n \
      --arg system "$(get_system_prompt)" \
      --arg user_message "$user_message" \
      --arg model "$model" \
      --argjson tokens "$TOKENS" \
      --argjson tools "$tools" \
      '{model: $model, max_output_tokens: $tokens, input: [{role: "system", content: [{type: "input_text", text: $system}]}, {role: "user", content: [{type: "input_text", text: $user_message}]}], tools: $tools}')

    local raw_response
    raw_response=$(echo "$request" | ${pkgs.httpie}/bin/http POST https://api.openai.com/v1/responses \
        "Authorization:Bearer $api_key" \
        "Content-Type:application/json")
    local http_status=$?

    if ! ensure_request_success "$http_status" "$raw_response"; then
      exit 1
    fi

    local output
    output=$(echo "$raw_response" | ${pkgs.jq}/bin/jq -r 'if .output_text and (.output_text|type=="string") and (.output_text|length>0) then .output_text else ([ .output[]? | select(.type=="message") | .content[]? | select(.type=="output_text") | .text // empty ] | join("\n\n")) // "No text output found." end' | ${pkgs.gnused}/bin/sed -e '/<thinking>/,/<\/thinking>/d' -e '/<drafts>/,/<\/drafts>/d')

    if [ "$FORMAT" = true ]; then
      format_cards "$output"
    else
      echo "$output"
    fi
  }

  ankigen_gemini() {
    local api_key
    if ! api_key="$(${secretsmanager}/bin/secretsmanager get GEMINI_API_KEY --pass-path gemini-api-key)"; then
      exit 1
    fi
    local user_message
    user_message=$(build_user_message "$1")

    local model="gemini-2.5-pro"
    [ "$FAST" = true ] && model="gemini-2.5-flash"

    if [ "$USE_WEB" = true ]; then
      echo "Warning: Gemini web search tooling is not supported yet; continuing without web search." >&2
    fi

    local request=$(${pkgs.jq}/bin/jq -n \
      --arg system "$(get_system_prompt)" \
      --arg user_message "$user_message" \
      --argjson tokens "$TOKENS" \
      '{system_instruction: {parts: [{text: $system}]}, contents: [{role: "user", parts: [{text: $user_message}]}], generation_config: {max_output_tokens: $tokens, temperature: 0.3}}')

    local endpoint="https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$api_key"

    local raw_response
    raw_response=$(echo "$request" | ${pkgs.httpie}/bin/http POST "$endpoint" \
        "Content-Type:application/json")
    local http_status=$?

    if ! ensure_request_success "$http_status" "$raw_response"; then
      exit 1
    fi

    local output
    output=$(echo "$raw_response" | ${pkgs.jq}/bin/jq -r '[.candidates[]?.content.parts[]?.text // empty] | map(select(length>0)) | join("\n\n") | if length>0 then . else "No text output found." end' | ${pkgs.gnused}/bin/sed -e '/<thinking>/,/<\/thinking>/d' -e '/<drafts>/,/<\/drafts>/d')

    if [ "$FORMAT" = true ]; then
      format_cards "$output"
    else
      echo "$output"
    fi
  }

  TEMP=$(${pkgs.util-linux}/bin/getopt -o hbdfrwt: --long help,no-cache,debug,fast,raw,web,token: -n "$0" -- "$@")
  if [ $? != 0 ]; then
    echo "Error parsing options" >&2
    exit 1
  fi
  eval set -- "$TEMP"

  while true; do
    case "$1" in
      -h|--help) echo "Usage: $0 [claude|chatgpt|gemini] [-b|--no-cache] [-d|--debug] [-f|--fast] [-r|--raw] [-w|--web] [-t|--token N] \"question\""; exit 0 ;;
      -b|--no-cache) NO_CACHE=true; shift ;;
      -d|--debug) DEBUG=1; shift ;;
      -f|--fast) FAST=true; shift ;;
      -r|--raw) FORMAT=false; shift ;;
      -w|--web) USE_WEB=true; shift ;;
      -t|--token) TOKENS="$2"; shift 2 ;;
      --) shift; break ;;
      *) echo "Invalid option: $1"; exit 1 ;;
    esac
  done

  [ $DEBUG -eq 1 ] && set -x

  if [[ $# -gt 0 && "$1" =~ ^(claude|chatgpt|gemini)$ ]]; then
    PROVIDER="$1"
    shift
    QUESTION="$*"
  else
    QUESTION="$*"
    if [ -z "$QUESTION" ]; then
      PROVIDER=$(echo -e "claude\nchatgpt\ngemini" | ${pkgs.fzf}/bin/fzf --prompt="Select AI model: " --height=40% --reverse)
      if [ -z "$PROVIDER" ]; then
        echo "No model selected." >&2
        exit 1
      fi
      read -p "Enter a question: " QUESTION
    else
      PROVIDER=$(echo -e "claude\nchatgpt\ngemini" | ${pkgs.fzf}/bin/fzf --prompt="Select AI model: " --height=40% --reverse)
      if [ -z "$PROVIDER" ]; then
        echo "No model selected." >&2
        exit 1
      fi
    fi
  fi

  ankigen_$PROVIDER "$QUESTION"
''
