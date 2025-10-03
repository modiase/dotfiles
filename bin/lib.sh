#!/usr/bin/env bash

EXIT_FAILURE=1
LOG_LEVEL=${LOG_LEVEL:-1}
COLOR_ENABLED=${COLOR_ENABLED:-true}
LOGGING_NO_PREFIX=${LOGGING_NO_PREFIX:-0}

COLOR_RESET='\033[0m'
COLOR_CYAN='\033[0;36m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_BLUE='\033[0;34m'
COLOR_YELLOW='\033[0;33m'
COLOR_WHITE='\033[0;37m'


log_info(){
	local msg="$1"
	if [[ ${LOG_LEVEL:-1} -ge 1 ]]; then
		log "$msg"
	fi
}

log_error(){
	local msg="$1"
	perror "$msg"
}

log_success(){
	local msg="$1"
	local prefix
	prefix=$(timestamp_prefix)
	colorize "$COLOR_GREEN" "${prefix}${msg}"
}

check(){
	local CMD="$1"
	command -v "${CMD}" &>/dev/null && printf "1" || printf "0"
}

debug(){
	local MSG="$1"
	if [[ ${DEBUG:-0} -gt 0 ]]
	then
		echo "${MSG}"
	fi
}

colorize(){
	local color="$1"
	local text="$2"
	if [[ "$COLOR_ENABLED" = true && -t 1 ]]; then
		echo -e "${color}${text}${COLOR_RESET}"
	else
		echo "$text"
	fi
}

timestamp_prefix(){
	if [[ "$LOGGING_NO_PREFIX" == "1" ]]; then
		printf ""
	else
		printf "[%s] " "$(date '+%H:%M:%S')"
	fi
}

log(){
	local MSG="$1"
	local prefix
	prefix=$(timestamp_prefix)
	colorize "$COLOR_CYAN" "${prefix}${MSG}"
}

perror(){
	local MSG="$1"
	local prefix
	prefix=$(timestamp_prefix)
	>&2 colorize "$COLOR_RED" "${prefix}${MSG}"
}

process_output(){
	local label="$1"
	local color="$2"
	local is_stderr=${3:-false}
	while IFS= read -r line; do
		[[ -z "$line" ]] && continue
		if [[ ${LOG_LEVEL:-1} -lt 2 && "$is_stderr" != "true" ]]; then
			continue
		fi
		local prefix=""
		if [[ "$LOGGING_NO_PREFIX" != "1" ]]; then
			prefix="[$(date '+%H:%M:%S')] [$label] "
		fi
		local formatted="${prefix}${line}"
		if [[ "$is_stderr" = "true" ]]; then
			>&2 colorize "$COLOR_YELLOW" "$formatted"
		else
			colorize "$color" "$formatted"
		fi
	done
}

run_logged(){
	local label="$1"
	local stdout_color="$2"
	shift 2
	log_info "${label} started"
	local status=0
	(
	  set -o pipefail
	  "${@}" > >(process_output "$label" "$stdout_color" false) \
	            2> >(process_output "$label" "$COLOR_YELLOW" true)
	) || status=$?
	if [[ $status -ne 0 ]]; then
		log_error "${label} failed (exit ${status})"
		return $status
	fi
	log_success "${label} completed"
	return 0
}

get_profile_file(){
	local platform=$1
	case "${PLATFORM}" in
		Darwin)
			printf ".zprofile"
			;;
		*)
			perror "Unsupported platform"
			exit $EXIT_FAILURE
			;;
	esac


}
get_rc_file(){
	local platform=$1
	case "${PLATFORM}" in
		Darwin)
			printf ".zshrc"
			;;
		*)
			perror "Unsupported platform"
			exit $EXIT_FAILURE
			;;
	esac
}

ensure_profile(){
	if [[ ! -f "~/${PROFILE_FILE}" ]]; then
		touch ~/"${PROFILE_FILE}"
	fi
}

profile_add(){
	local statement="$1"
	debug "profile add: ${statement}"

	ensure_profile
	if [[ "$(grep ${statement} ~/"${PROFILE_FILE}" && printf "1" || printf "0")" == "0" ]]; then
		debug "Adding '${statement}' to "${PROFILE_FILE}""
		echo "${statement}" >> ~/"${PROFILE_FILE}"
	else
		debug "statement already found in "${PROFILE_FILE}""
	fi
}

ensure_rc(){
	if [[ ! -f "~/${RC_FILE}" ]]; then
		touch ~/"${RC_FILE}"
	fi
}

rc_add(){
	local statement="$1"
	debug "rc add: ${statement}"

	ensure_rc
	if [[ "$(grep "${statement}" ~/"${RC_FILE}" && printf "1" || printf "0")" == "0" ]]; then
		debug "Adding '${statement}' to "${RC_FILE}""
		echo "${statement}" >> ~/"${RC_FILE}"
	else
		debug "statement already found in "${RC_FILE}""
	fi
}

if [[ ${DEBUG:-0} -gt 1 ]]; then
	set -x
fi
