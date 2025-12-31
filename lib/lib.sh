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

log_to_system() {
    local level="$1"
    local msg="$2"
    local syslog_level="$level"
    local os
    os=$(uname -s)

    case "$level" in
        warn) syslog_level="warning" ;;
        error) syslog_level="err" ;;
    esac

    case "$os" in
        Linux)
            if command -v systemd-cat >/dev/null 2>&1; then
                echo "$msg" | systemd-cat -t "dotfiles-activate" -p "$syslog_level"
            elif command -v logger >/dev/null 2>&1; then
                logger -t "dotfiles-activate" -p "user.${syslog_level}" "$msg"
            fi
            ;;
        Darwin)
            local logdir="$HOME/Library/Logs"
            local logfile="$logdir/dotfiles-activate.log"

            if [ ! -d "$logdir" ]; then
                mkdir -p "$logdir"
            fi

            local timestamp
            timestamp=$(date '+%Y-%m-%d %H:%M:%S')
            printf "%s [%s] %s\n" "$timestamp" "$level" "$msg" >>"$logfile"
            ;;
    esac
}

log_info() {
    local msg="$1"
    log_to_system "info" "$msg"
    [[ ${LOG_LEVEL:-1} -ge 1 ]] && log "$msg"
}

log_error() {
    local msg="$1"
    log_to_system "error" "$msg"
    perror "$msg"
}

log_success() {
    local msg="$1"
    log_to_system "info" "$msg"
    [[ ${PRETTY:-1} -eq 1 ]] && echo -e "${COLOR_GREEN}${msg}${COLOR_RESET}" && return
    _print_log_line "success" "$msg" "" "$COLOR_CYAN" "$COLOR_GREEN" false
}

check() {
    local CMD="$1"
    command -v "${CMD}" &>/dev/null && printf "1" || printf "0"
}

debug() {
    [[ ${DEBUG:-0} -gt 0 ]] && echo "$1"
}

colorize() {
    local color="$1"
    local text="$2"
    local output="$text"
    [[ "$COLOR_ENABLED" = true && -t 1 ]] && output="${color}${text}${COLOR_RESET}"
    echo -e "$output"
}

timestamp_prefix() {
    [[ "$LOGGING_NO_PREFIX" == "1" ]] && return
    printf "%s" "$(date '+%H:%M:%S')"
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
        normalized_label="main"
    fi

    if ((${#normalized_label} > 20)); then
        normalized_label="${normalized_label:0:20}"
    fi

    padded_label="$(_pad_center "$normalized_label" 20)"
    padded_level="$(_pad_center "$level" 7)"

    local compose_fn=_compose_line_plain
    if [[ "$is_err" = true ]]; then
        _supports_color_stderr && compose_fn=_compose_line
        $compose_fn "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message" >&2
        echo >&2
    else
        _supports_color_stdout && compose_fn=_compose_line
        $compose_fn "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message"
        echo
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
    local label_color="${2:-}"
    local is_stderr=${3:-false}
    local level="info"
    local console_color="$COLOR_WHITE"

    [[ "$is_stderr" = "true" ]] && level="warn" && console_color="$COLOR_YELLOW"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        log_to_system "$level" "[$label] $line"

        if [[ ${PRETTY:-1} -eq 0 ]] && [[ ${LOG_LEVEL:-1} -ge 2 ]]; then
            _print_log_line "$level" "$line" "$label" "${label_color:-$COLOR_CYAN}" "$console_color" "$is_stderr"
        fi
    done
}

run_logged() {
    local label="$1"
    local stdout_color="$2"
    shift 2
    local status=0

    if [[ -t 2 ]] && [[ ${LOG_LEVEL:-1} -lt 3 ]] && [[ ${PRETTY:-1} -eq 1 ]]; then
        log_to_system "info" "${label} started"

        local tmpfile
        tmpfile=$(mktemp)
        trap 'rm -f "$tmpfile"' RETURN

        (
            set -o pipefail
            "${@}" > >(while IFS= read -r line; do
                echo "$line" >"$tmpfile"
                process_output "$label" "" false <<<"$line"
            done) \
            2> >(while IFS= read -r line; do
                echo "$line" >"$tmpfile"
                process_output "$label" "" true <<<"$line"
            done)
        ) &
        local cmd_pid=$!

        shopt -s checkwinsize
        local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
        local i=0

        while kill -0 $cmd_pid 2>/dev/null; do
            local max_width=$((COLUMNS - 5))
            local latest
            latest=$(cat "$tmpfile" 2>/dev/null | tail -1 || echo "")
            local spinner_display="${COLOR_CYAN}${spinner_chars:$i:1}${COLOR_RESET}"
            local display="${spinner_display}  ${label}"

            if [[ -n "$latest" ]]; then
                local max_msg_len=$((max_width - ${#label} - 6))
                if [[ ${#latest} -gt $max_msg_len ]]; then
                    if [[ $max_msg_len -gt 3 ]]; then
                        latest="${latest:0:$((max_msg_len - 3))}..."
                    else
                        latest=""
                    fi
                fi
                [[ -n "$latest" ]] && display="${display} | ${latest}"
            fi

            printf "\r\033[K%b" "$display" >&2
            i=$(((i + 1) % ${#spinner_chars}))
            sleep 0.1
        done

        wait $cmd_pid || status=$?

        if [[ $status -eq 0 ]]; then
            printf "\r\033[K${COLOR_GREEN}✓${COLOR_RESET}  %s\n" "$label" >&2
            log_to_system "info" "${label} completed"
        else
            printf "\r\033[K${COLOR_RED}✗${COLOR_RESET}  %s\n" "$label" >&2
            log_to_system "error" "${label} failed (exit ${status})"
            log_error "${label} failed (exit ${status})"
            return $status
        fi
    else
        log_info "${label} started"
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
    fi
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
