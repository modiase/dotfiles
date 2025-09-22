{ pkgs, lib, ... }:

pkgs.writeShellScriptBin "ankigen" ''
   set -euo pipefail

   DEBUG=0
   NO_CACHE=false
   USE_WEB=false
   FAST=false
   TOKENS=2000



   get_api_key() {
      local key_name="$1"
      case "$(uname)" in
          Darwin)
              security find-generic-password -a "$USER" -s "$key_name" -w
              ;;
          Linux)
              pass show "$key_name" | head -n1
              ;;
          *)
              echo "Error: Unsupported OS $(uname)" >&2
              return 1
              ;;
      esac
  }

   get_system_prompt() {
     local url="https://gist.githubusercontent.com/modiase/88cbb2e7947a4ae970a91d9e335ab59c/raw/anki.txt"
     [ "$NO_CACHE" = true ] && url="$url?t=$(date +%s)"
     ${pkgs.httpie}/bin/http --body GET "$url"
   }

   ankigen_claude() {
     local api_key="$(get_api_key "ANTHROPIC_API_KEY")"
     local model="claude-opus-4-1-20250805"
     [ "$FAST" = true ] && model="claude-3-5-haiku-20241022"

     local tools='[]'
     [ "$USE_WEB" = true ] && tools='[{"type": "web_search_20250305", "name": "web_search", "max_uses": 5}]'

     local request=$(${pkgs.jq}/bin/jq -n \
       --arg system "$(get_system_prompt)" \
       --arg user_message "Please create an Anki card for the following question: $1" \
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

     if [ $http_status -ne 0 ]; then
       echo -e "\033[0;31mHTTP request failed with status $http_status:\033[0m" >&2
       echo -e "\033[0;31m$raw_response\033[0m" >&2
       exit 1
     fi

     local error_check=$(echo "$raw_response" | ${pkgs.jq}/bin/jq -r '.error // empty')
     if [ -n "$error_check" ]; then
       echo -e "\033[0;31mAPI Error:\033[0m" >&2
       echo -e "\033[0;31m$raw_response\033[0m" >&2
       exit 1
     fi

     echo "$raw_response" | ${pkgs.jq}/bin/jq -r '.content[0].text' | ${pkgs.gnused}/bin/sed '/<thinking>/,/<\/thinking>/d'
   }

   ankigen_chatgpt() {
     local api_key="$(get_api_key "OPENAI_API_KEY")"

     local model="gpt-4.1"
     [ "$FAST" = true ] && model="o4-mini"

     local tools='[]'
     [ "$USE_WEB" = true ] && tools='[{"type":"web_search"}]'

     local request=$(${pkgs.jq}/bin/jq -n \
       --arg system "$(get_system_prompt)" \
       --arg user_message "Please create an Anki card for the following question: $1" \
       --arg model "$model" \
       --argjson tokens "$TOKENS" \
       --argjson tools "$tools" \
       '{model: $model, max_output_tokens: $tokens, input: [{role: "system", content: [{type: "input_text", text: $system}]}, {role: "user", content: [{type: "input_text", text: $user_message}]}], tools: $tools}')

     local raw_response
     raw_response=$(echo "$request" | ${pkgs.httpie}/bin/http POST https://api.openai.com/v1/responses \
         "Authorization:Bearer $api_key" \
         "Content-Type:application/json")
     local http_status=$?

     if [ $http_status -ne 0 ]; then
       echo -e "\033[0;31mHTTP request failed with status $http_status:\033[0m" >&2
       echo -e "\033[0;31m$raw_response\033[0m" >&2
       exit 1
     fi

     local error_check=$(echo "$raw_response" | ${pkgs.jq}/bin/jq -r '.error // empty')
     if [ -n "$error_check" ]; then
       echo -e "\033[0;31mAPI Error:\033[0m" >&2
       echo -e "\033[0;31m$raw_response\033[0m" >&2
       exit 1
     fi

     echo "$raw_response" | ${pkgs.jq}/bin/jq -r 'if .output_text and (.output_text|type=="string") and (.output_text|length>0) then .output_text else ([ .output[]? | select(.type=="message") | .content[]? | select(.type=="output_text") | .text // empty ] | join("\n\n")) // "No text output found." end' | ${pkgs.gnused}/bin/sed '/<thinking>/,/<\/thinking>/d'
   }

   TEMP=$(${pkgs.util-linux}/bin/getopt -o hbdfwt: --long help,no-cache,debug,fast,web,token: -n "$0" -- "$@")
   if [ $? != 0 ]; then
     echo "Error parsing options" >&2
     exit 1
   fi
   eval set -- "$TEMP"

   while true; do
     case "$1" in
       -h|--help) echo "Usage: $0 [model] [-b|--no-cache] [-d|--debug] [-f|--fast] [-w|--web] [-t|--token N] \"question\""; exit 0 ;;
       -b|--no-cache) NO_CACHE=true; shift ;;
       -d|--debug) DEBUG=1; shift ;;
       -f|--fast) FAST=true; shift ;;
       -w|--web) USE_WEB=true; shift ;;
       -t|--token) TOKENS="$2"; shift 2 ;;
       --) shift; break ;;
       *) echo "Invalid option: $1"; exit 1 ;;
     esac
   done

   [ $DEBUG -eq 1 ] && set -x

   if [[ $# -gt 0 && "$1" =~ ^(claude|chatgpt)$ ]]; then
     PROVIDER="$1"
     shift
     QUESTION="$*"
   else
     QUESTION="$*"
     if [ -z "$QUESTION" ]; then
       PROVIDER=$(echo -e "claude\nchatgpt" | ${pkgs.fzf}/bin/fzf --prompt="Select AI model: " --height=40% --reverse)
       read -p "Enter a question: " QUESTION
     else
       PROVIDER=$(echo -e "claude\nchatgpt" | ${pkgs.fzf}/bin/fzf --prompt="Select AI model: " --height=40% --reverse)
     fi
   fi

   ankigen_$PROVIDER "$QUESTION"
''
