#!/usr/bin/env bash
# shellcheck disable=SC2034
EXIT_FAILURE=1
export LOG_LEVEL=${LOG_LEVEL:-2}
COLOR_ENABLED=${COLOR_ENABLED:-true}
LOGGING_NO_PREFIX=${LOGGING_NO_PREFIX:-0}

COLOR_RESET='\033[0m'
COLOR_CYAN='\033[0;36m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
# shellcheck disable=SC2034
COLOR_YELLOW='\033[0;33m'
# shellcheck disable=SC2034
COLOR_WHITE='\033[0;37m'

_supports_color_stdout() { [[ "$COLOR_ENABLED" = true && -t 1 ]]; }
_supports_color_stderr() { [[ "$COLOR_ENABLED" = true && -t 2 ]]; }

_fmt() {
    local color="$1"
    shift
    printf "%b%s%b" "$color" "$1" "$COLOR_RESET"
}

_compose_line() {
    local ts_color="$1" ts_text="$2" sep1="$3" lbl_color="$4" lbl_text="$5"
    local sep2="$6" lvl_color="$7" lvl_text="$8" sep3="$9"
    shift 9
    local msg_color="$1" msg_text="$2"

    local out=""
    out+="$(_fmt "$ts_color" "$ts_text")$sep1"
    [[ -n "$lbl_text" ]] && out+="$(_fmt "$lbl_color" "$lbl_text")$sep2"
    out+="$(_fmt "$lvl_color" "$lvl_text")$sep3$(_fmt "$msg_color" "$msg_text")"
    printf "%s" "$out"
}

_compose_line_plain() {
    local ts_text="$2" sep1="$3" lbl_text="$5" sep2="$6" lvl_text="$8" sep3="$9"
    shift 9
    local msg_text="$2"
    local out="${ts_text}${sep1}"
    [[ -n "$lbl_text" ]] && out+="${lbl_text}${sep2}"
    out+="${lvl_text}${sep3}${msg_text}"
    printf "%s" "$out"
}

_pad_center() {
    local text="$1" width="$2" length=${#1}

    ((length >= width)) && {
        printf "%s" "$text"
        return
    }

    local padding=$((width - length))
    local left=$((padding / 2))
    local right=$((padding - left))
    local left_pad="" right_pad=""

    printf -v left_pad "%*s" "$left" ""
    printf -v right_pad "%*s" "$right" ""
    printf "%s%s%s" "$left_pad" "$text" "$right_pad"
}

log_to_system() {
    local level="$1" msg="$2"
    local syslog_level="$level"
    local os
    os=$(uname -s)

    case "$level" in
        warn) syslog_level="warning" ;;
        error) syslog_level="err" ;;
    esac

    case "$os" in
        Linux)
            command -v systemd-cat >/dev/null 2>&1 && {
                echo "$msg" | systemd-cat -t "dotfiles-activate" -p "$syslog_level"
                return
            }
            command -v logger >/dev/null 2>&1 &&
                logger -t "dotfiles-activate" -p "user.${syslog_level}" "$msg"
            ;;
        Darwin)
            local logfile="$HOME/Library/Logs/dotfiles-activate.log"
            mkdir -p "${logfile%/*}"
            printf "%s | %s | %s | %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$(_pad_center "main" 20)" "$(_pad_center "$level" 7)" "$msg" >>"$logfile"
            ;;
    esac
}

log_trace_to_pipe() {
    [[ ${LOG_LEVEL:-2} -lt 4 ]] && {
        cat >/dev/null
        return
    }

    local os padded_level
    os=$(uname -s)
    padded_level="$(_pad_center "trace" 7)"

    case "$os" in
        Darwin)
            local logfile="$HOME/Library/Logs/dotfiles-activate.log"
            mkdir -p "${logfile%/*}"
            while IFS= read -r line; do
                [[ "$line" == *"logging-utils.sh:"* ]] && continue
                local label="${line%% | *}"
                local msg="${line#* | }"
                printf "%s | %s | %s | %s\n" \
                    "$(date '+%Y-%m-%d %H:%M:%S')" "$(_pad_center "$label" 20)" "$padded_level" "$msg" >>"$logfile"
            done
            ;;
        Linux)
            if command -v systemd-cat >/dev/null 2>&1; then
                while IFS= read -r line; do
                    [[ "$line" == *"logging-utils.sh:"* ]] && continue
                    local label="${line%% | *}"
                    local msg="${line#* | }"
                    printf "%s | %s | %s | %s\n" \
                        "$(date '+%Y-%m-%d %H:%M:%S')" "$(_pad_center "$label" 20)" "$padded_level" "$msg"
                done | systemd-cat -t "dotfiles-activate" -p "debug"
            elif command -v logger >/dev/null 2>&1; then
                while IFS= read -r line; do
                    [[ "$line" == *"logging-utils.sh:"* ]] && continue
                    local label="${line%% | *}"
                    local msg="${line#* | }"
                    logger -t "dotfiles-activate" -p "user.debug" \
                        "$(date '+%Y-%m-%d %H:%M:%S') | $(_pad_center "$label" 20) | $padded_level | $msg"
                done
            else
                cat >/dev/null
            fi
            ;;
        *)
            cat >/dev/null
            ;;
    esac
}

timestamp_prefix() {
    [[ "$LOGGING_NO_PREFIX" == "1" ]] && return
    printf "%s" "$(date '+%H:%M:%S')"
}

_print_log_line() {
    local level="$1" message="$2" label="${3:-}" label_color="${4:-$COLOR_CYAN}"
    local msg_color="${5:-$COLOR_WHITE}" is_err="${6:-false}"
    local ts sep=" | " normalized_label="$label"
    ts="$(timestamp_prefix)"

    [[ -z "$normalized_label" ]] && normalized_label="main"
    ((${#normalized_label} > 20)) && normalized_label="${normalized_label:0:20}"

    local padded_label padded_level
    padded_label="$(_pad_center "$normalized_label" 20)"
    padded_level="$(_pad_center "$level" 7)"

    local compose_fn=_compose_line_plain
    [[ "$is_err" = true ]] && {
        _supports_color_stderr && compose_fn=_compose_line
        $compose_fn "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message" >&2
        echo >&2
        return
    }

    _supports_color_stdout && compose_fn=_compose_line
    $compose_fn "$COLOR_WHITE" "$ts" "$sep" "$label_color" "$padded_label" "$sep" "$COLOR_WHITE" "$padded_level" "$sep" "$msg_color" "$message"
    echo
}

log_error() {
    local msg="$1"
    log_to_system "error" "$msg"
    _print_log_line "error" "$msg" "" "$COLOR_CYAN" "$COLOR_RED" true
}

log_info() {
    local msg="$1"
    log_to_system "info" "$msg"
    [[ ${LOG_LEVEL:-2} -ge 2 ]] && _print_log_line "info" "$msg" "" "$COLOR_CYAN" "$COLOR_WHITE" false || true
}

log_debug() {
    local msg="$1"
    [[ ${LOG_LEVEL:-2} -ge 3 ]] && _print_log_line "debug" "$msg" "" "$COLOR_CYAN" "$COLOR_WHITE" false || true
}

log_success() {
    local msg="$1"
    log_to_system "info" "$msg"
    [[ ${LOG_LEVEL:-2} -ge 2 ]] && echo -e "${COLOR_GREEN}${msg}${COLOR_RESET}" || true
}

__wrap_log_fn() {
    local fn_name="$1"
    local internal_name="__${fn_name}"
    eval "$internal_name() $(declare -f "$fn_name" | tail -n +2)"
    eval "${fn_name}() {
        local __opts__=\$-
        { set +x; } 2>/dev/null
        ${internal_name} \"\$@\"
        local rc=\$?
        [[ \$__opts__ == *x* ]] && set -x
        return \$rc
    }"
}

check() {
    local CMD="$1"
    command -v "${CMD}" &>/dev/null && printf "1" || printf "0"
}

colorize() {
    local color="$1" text="$2"
    local output="$text"
    [[ "$COLOR_ENABLED" = true && -t 1 ]] && output="${color}${text}${COLOR_RESET}"
    echo -e "$output"
}

run_logged() {
    local label="$1"
    shift
    local status=0

    [[ ${LOG_LEVEL:-2} -ge 3 ]] && {
        log_info "${label} started"
        (
            set -o pipefail
            "$@" 2>&1 | while IFS= read -r line; do
                [[ -n "$line" ]] && _print_log_line "debug" "$line" "$label" "$COLOR_CYAN" "$COLOR_WHITE" false
            done
        ) || status=$?
        if [[ $status -eq 0 ]]; then
            log_success "${label} completed"
        else
            log_error "${label} failed (exit ${status})"
        fi
        return $status
    }

    [[ ! -t 2 ]] && {
        echo "→ ${label}" >&2
        log_to_system "info" "${label} started"
        "$@" 2>&1 || status=$?
        if [[ $status -eq 0 ]]; then
            echo "✓ ${label}" >&2
            log_to_system "info" "${label} completed"
        else
            echo "✗ ${label} (exit ${status})" >&2
            log_to_system "error" "${label} failed (exit ${status})"
        fi
        return $status
    }

    # TTY spinner mode
    log_to_system "info" "${label} started"

    local tmpfile
    tmpfile=$(mktemp)
    add_exit_hook "rm -f '$tmpfile'"

    (
        set -o pipefail
        "$@" > >(while IFS= read -r line; do
            echo "$line" >"$tmpfile"
            log_to_system "info" "[$label] $line"
        done) \
        2> >(while IFS= read -r line; do
            echo "$line" >"$tmpfile"
            log_to_system "warn" "[$label] $line"
        done)
    ) &
    local cmd_pid=$!

    shopt -s checkwinsize
    local spinner_chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    local i=0

    while kill -0 $cmd_pid 2>/dev/null; do
        local max_width=$((${COLUMNS:-80} - 5))
        local latest
        latest=$(cat "$tmpfile" 2>/dev/null | tail -1 || echo "")
        local spinner_display="${COLOR_CYAN}${spinner_chars:$i:1}${COLOR_RESET}"
        local display="${spinner_display}  ${label}"

        [[ -n "$latest" ]] && {
            local max_msg_len=$((max_width - ${#label} - 6))
            ((${#latest} > max_msg_len)) && {
                ((max_msg_len > 3)) && latest="${latest:0:$((max_msg_len - 3))}..." || latest=""
            }
            [[ -n "$latest" ]] && display="${display} | ${latest}"
        }

        printf "\r\033[K%b" "$display" >&2
        i=$(((i + 1) % ${#spinner_chars}))
        sleep 0.1
    done

    wait $cmd_pid || status=$?

    [[ $status -eq 0 ]] && {
        printf "\r\033[K${COLOR_GREEN}✓${COLOR_RESET}  %s\n" "$label" >&2
        log_to_system "info" "${label} completed"
        return 0
    }

    printf "\r\033[K${COLOR_RED}✗${COLOR_RESET}  %s\n" "$label" >&2
    log_to_system "error" "${label} failed (exit ${status})"
    log_error "${label} failed (exit ${status})"
    return $status
}

__wrap_log_fn log_error
__wrap_log_fn log_info
__wrap_log_fn log_debug
__wrap_log_fn log_success
__wrap_log_fn run_logged

enable_log_tracing() {
    exec {BASH_XTRACEFD}> >(log_trace_to_pipe)
    PS4='${BASH_SOURCE[0]##*/}:${LINENO} | '
    set -x
}
