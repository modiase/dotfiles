#!/usr/bin/env bash

EXIT_FAILURE=1
LOG_LEVEL=${LOG_LEVEL:-1}
COLOR_ENABLED=${COLOR_ENABLED:-true}
LOGGING_NO_PREFIX=${LOGGING_NO_PREFIX:-0}

COLOR_RESET='\033[0m'
COLOR_CYAN='\033[0;36m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
# shellcheck disable=SC2034
COLOR_WHITE='\033[0;37m'

# Render helpers for multi-segment colored lines
_supports_color_stdout() { [[ "$COLOR_ENABLED" = true && -t 1 ]]; }
_supports_color_stderr() { [[ "$COLOR_ENABLED" = true && -t 2 ]]; }

_fmt() {
    # $1=color $2=text
    local color="$1"
    shift
    local text="$1"
    printf "%b%s%b" "$color" "$text" "$COLOR_RESET"
}

_compose_line() {
    # Build a single string with colored segments:
    # args: ts_color ts_text sep label_color label_text sep level_color level_text sep msg_color msg_text
    local ts_color="$1"
    local ts_text="$2"
    local sep1="$3"
    local lbl_color="$4"
    local lbl_text="$5"
    local sep2="$6"
    local lvl_color="$7"
    local lvl_text="$8"
    local sep3="$9"
    shift 9
    local msg_color="$1"
    local msg_text="$2"

    local out=""
    out+="$(_fmt "$ts_color" "$ts_text")"
    out+="$sep1"
    if [[ -n "$lbl_text" ]]; then
        out+="$(_fmt "$lbl_color" "$lbl_text")"
        out+="$sep2"
    fi
    out+="$(_fmt "$lvl_color" "$lvl_text")"
    out+="$sep3"
    out+="$(_fmt "$msg_color" "$msg_text")"
    printf "%s" "$out"
}

_compose_line_plain() {
    # Plain (no color) equivalent of _compose_line for non-TTY/piped output
    local ts_text="$2"
    local sep1="$3"
    local lbl_text="$5"
    local sep2="$6"
    local lvl_text="$8"
    local sep3="$9"
    shift 9
    local msg_text="$2"
    local out="${ts_text}${sep1}"
    if [[ -n "$lbl_text" ]]; then
        out+="${lbl_text}${sep2}"
    fi
    out+="${lvl_text}${sep3}${msg_text}"
    printf "%s" "$out"
}

# Center pad text to a fixed width using spaces
_pad_center() {
    local text="$1"
    local width="$2"
    local length=${#text}

    if ((length >= width)); then
        printf "%s" "$text"
        return
    fi

    local padding=$((width - length))
    local left=$((padding / 2))
    local right=$((padding - left))
    local left_pad=""
    local right_pad=""

    printf -v left_pad "%*s" "$left" ""
    printf -v right_pad "%*s" "$right" ""
    printf "%s%s%s" "$left_pad" "$text" "$right_pad"
}

log_info() {
    local msg="$1"
    if [[ ${LOG_LEVEL:-1} -ge 1 ]]; then
        log "$msg"
    fi
}

log_error() {
    local msg="$1"
    perror "$msg"
}

log_success() {
    local msg="$1"
    _print_log_line "success" "$msg" "" "$COLOR_CYAN" "$COLOR_GREEN" false
}

check() {
    local CMD="$1"
    command -v "${CMD}" &>/dev/null && printf "1" || printf "0"
}

debug() {
    local MSG="$1"
    if [[ ${DEBUG:-0} -gt 0 ]]; then
        echo "${MSG}"
    fi
}

colorize() {
    local color="$1"
    local text="$2"
    if [[ "$COLOR_ENABLED" = true && -t 1 ]]; then
        echo -e "${color}${text}${COLOR_RESET}"
    else
        echo "$text"
    fi
}

timestamp_prefix() {
    if [[ "$LOGGING_NO_PREFIX" == "1" ]]; then
        printf ""
    else
        printf "%s" "$(date '+%H:%M:%S')"
    fi
}

# Unified log line printer
_print_log_line() {
    # $1=level (info|warn|error|success) $2=message $3=label(optional) $4=label_color $5=msg_color $6=is_stderr(true|false)
    local level="$1"
    local message="$2"
    local label="${3:-}"
    local label_color="${4:-$COLOR_CYAN}"
    local msg_color="${5:-$COLOR_WHITE}"
    local is_err="${6:-false}"
    local ts
    ts="$(timestamp_prefix)"
    local sep=" | "
    local padded_label
    local padded_level
    local normalized_label="$label"

    if [[ -z "$normalized_label" ]]; then
        normalized_label="root"
    fi

    if ((${#normalized_label} > 20)); then
        normalized_label="${normalized_label:0:20}"
    fi

    padded_label="$(_pad_center "$normalized_label" 20)"
    padded_level="$(_pad_center "$level" 7)"

    if [[ "$is_err" = true ]]; then
        if _supports_color_stderr; then
            _compose_line "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message" 1>&2
            echo 1>&2
        else
            _compose_line_plain "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message" 1>&2
            echo 1>&2
        fi
    else
        if _supports_color_stdout; then
            _compose_line "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message"
            echo
        else
            _compose_line_plain "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message"
            echo
        fi
    fi
}

log() {
    local msg="$1"
    _print_log_line "info" "$msg" "" "$COLOR_CYAN" "$COLOR_WHITE" false
}

perror() {
    local msg="$1"
    _print_log_line "error" "$msg" "" "$COLOR_CYAN" "$COLOR_RED" true
}

process_output() {
    local label="$1"
    local label_color="$2"
    local is_stderr=${3:-false}
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ ${LOG_LEVEL:-1} -lt 2 && "$is_stderr" != "true" ]]; then
            continue
        fi
        if [[ "$is_stderr" = "true" ]]; then
            _print_log_line "warn" "$line" "$label" "$label_color" "$COLOR_YELLOW" true
        else
            _print_log_line "info" "$line" "$label" "$label_color" "$COLOR_WHITE" false
        fi
    done
}

run_logged() {
    local label="$1"
    local stdout_color="$2"
    shift 2
    log_info "${label} started"
    local status=0
    (
        set -o pipefail
        "${@}" > >(process_output "$label" "$stdout_color" false) \
        2> >(process_output "$label" "$stdout_color" true)
    ) || status=$?
    if [[ $status -ne 0 ]]; then
        log_error "${label} failed (exit ${status})"
        return $status
    fi
    log_success "${label} completed"
    return 0
}

get_profile_file() {
    local platform=$1
    case "${platform}" in
        Darwin)
            printf ".zprofile"
            ;;
        *)
            perror "Unsupported platform"
            exit $EXIT_FAILURE
            ;;
    esac

}
get_rc_file() {
    local platform=$1
    case "${platform}" in
        Darwin)
            printf ".zshrc"
            ;;
        *)
            perror "Unsupported platform"
            exit $EXIT_FAILURE
            ;;
    esac
}

ensure_profile() {
    if [[ ! -f "$HOME/${PROFILE_FILE}" ]]; then
        touch "$HOME/${PROFILE_FILE}"
    fi
}

profile_add() {
    local statement="$1"
    debug "profile add: ${statement}"

    ensure_profile
    if [[ "$(grep "${statement}" "$HOME/${PROFILE_FILE}" && printf "1" || printf "0")" == "0" ]]; then
        debug "Adding '${statement}' to ${PROFILE_FILE}"
        echo "${statement}" >>"$HOME/${PROFILE_FILE}"
    else
        debug "statement already found in ${PROFILE_FILE}"
    fi
}

ensure_rc() {
    if [[ ! -f "$HOME/${RC_FILE}" ]]; then
        touch "$HOME/${RC_FILE}"
    fi
}

rc_add() {
    local statement="$1"
    debug "rc add: ${statement}"

    ensure_rc
    if [[ "$(grep "${statement}" "$HOME/${RC_FILE}" && printf "1" || printf "0")" == "0" ]]; then
        debug "Adding '${statement}' to ${RC_FILE}"
        echo "${statement}" >>"$HOME/${RC_FILE}"
    else
        debug "statement already found in ${RC_FILE}"
    fi
}

if [[ ${DEBUG:-0} -gt 1 ]]; then
    set -x
fi
