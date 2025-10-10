
#!/bin/sh -eu
# Minimal bootstrap script
# Build a minimal enviornment which can install packages using nix

on_exit(){
	if [[ $? != 0 ]]; then
		printf "bootstrap failed\n" >&2
	else
		printf "bootstrap complete\n"
	fi
}
trap on_exit EXIT

EXIT_FAILURE=1
if [[ -n $BASH_VERSION ]];then
	SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd -P)"
else
	echo "Unsupported shell. Bash required." >&2
	exit $EXIT_FAILURE
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
source "${REPO_ROOT}/lib/lib.sh"

ensure_xz(){
	if ! command -v xz &>/dev/null; then
		if test "$(uname)" = Linux; then
			if command -v apt &>/dev/null; then
				sudo apt update && sudo apt install -y xz-utils
			elif command -v yum &>/dev/null; then
				sudo yum update && sudo yum install -y xz
			elif command -v apk &>/dev/null; then
				apk update && apk add xz
			elif command -v nix &>/dev/null; then
				nix-env -iA nixpkgs.xz
			else
				perror "Could not determine an appropriate package manager to install 'xz'."
				exit $EXIT_FAILURE
			fi
		else
			perror "Please install 'xz'."
			exit $EXIT_FAILURE
		fi
	fi

}

ensure_tar(){
	if ! command -v tar &>/dev/null; then
		if test "$(uname)" = Linux; then
			if command -v apt &>/dev/null; then
				sudo apt update && sudo apt install -y tar
			elif command -v yum &>/dev/null; then
				sudo yum update && sudo yum install -y tar
			elif command -v apk &>/dev/null; then
				apk update && apk add tar
			elif command -v nix &>/dev/null; then
				nix-env -iA nixpkgs.tar
			else
				perror "Could not determine an appropriate package manager to install 'tar'."
				exit $EXIT_FAILURE
			fi
		else
			perror "Please install 'tar'"
			exit $EXIT_FAILURE
		fi
	fi

}

postinstall_nix(){
			source "${HOME}/.nix-profile/etc/profile.d/nix.sh"
}

linux_install_nix(){
			eval "$(command -v bash) <(curl -L https://nixos.org/nix/install) --no-daemon"
}

darwin_install_nix(){
			eval "$(command -v bash) <(curl -L https://nixos.org/nix/install)"
}

install_darwin_sudoers(){
	if [[ "$(uname)" != "Darwin" ]]; then
		return
	fi

	local sudoers_file="/etc/sudoers.d/${USER}_allow_darwin_rebuild"
	local source_file="${SCRIPT_DIR}/../lib/allow_darwin_rebuild"

	if [[ -f "$sudoers_file" ]]; then
		debug "Sudoers file already exists: $sudoers_file"
		return
	fi

	if [[ ! -f "$source_file" ]]; then
		perror "Source sudoers file not found: $source_file"
		exit $EXIT_FAILURE
	fi

	debug "Installing Darwin sudoers file: $sudoers_file"

	sudo mkdir -p "$(dirname "$sudoers_file")"
	sed "s/\${USER}/$USER/g" "$source_file" | sudo tee "$sudoers_file" > /dev/null

	if [[ $? -eq 0 ]]; then
		debug "Successfully installed sudoers file: $sudoers_file"
	else
		perror "Failed to install sudoers file: $sudoers_file"
		exit $EXIT_FAILURE
	fi
}



install_nix(){
	local platform=$1
	if [[ "$(check 'nix')" == "1" ]]; then
		debug "'nix' is already installed."
		return
	else
		debug "Installing 'nix'"
	fi


	ensure_tar
	ensure_xz
	case "${platform}" in
		Darwin)
			darwin_install_nix
			;;
		Linux)
			linux_install_nix
			;;

		*)
			perror "Unsupported platform: ${platform}."
			exit $EXIT_FAILURE
			;;
	esac

	postinstall_nix

}

install_platform_sudoers(){
	local platform=$1

	case "${platform}" in
		Darwin)
			install_darwin_sudoers
			;;
		Linux)
			debug "Linux detected - sudoers configuration should be handled via NixOS configuration.nix"
			;;
	esac
}

platform="$(uname)"
install_nix "$platform"
install_platform_sudoers "$platform"
