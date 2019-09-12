#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.
#
# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# DO NOT EDIT THIS FILE
# use configuration files like config-default.conf to set the build configuration
# check Armbian documentation for more info

SRC="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# fallback for Trusty
[[ -z "${SRC}" ]] && SRC="$(pwd)"

# check for whitespace in $SRC and exit for safety reasons
grep -q "[[:space:]]" <<<"${SRC}" && { echo "\"${SRC}\" contains whitespace. Not supported. Aborting." >&2 ; exit 1 ; }

cd "${SRC}" || exit

if [[ -f "${SRC}"/lib/general.sh ]]; then
	# shellcheck source=lib/general.sh
	source "${SRC}"/lib/general.sh
else
	echo "Error: missing build directory structure"
	echo "Please clone the full repository https://github.com/armbian/build/"
	exit 255
fi

if [[ -z "$CONFIG" && -n "$1" && -f "${SRC}/userpatches/config-$1.conf" ]]; then
	CONFIG="userpatches/config-$1.conf"
fi

if [[ -z "$CONFIG" && -z "$1" && ! -f "${SRC}/userpatches/config-default.conf" ]]; then
	display_alert "Create example config file using template" "config-default.conf" "info"
	mkdir -p $SRC/userpatches
	if [[ ! -f "${SRC}"/userpatches/config-example.conf ]]; then
		cp "${SRC}"/config/templates/config-example.conf "${SRC}"/userpatches/config-example.conf || exit 1
	fi
	ln -s config-example.conf "${SRC}"/userpatches/config-default.conf || exit 1
fi

if [[ -z "$CONFIG" && -f "${SRC}/userpatches/config-default.conf" ]]; then
	CONFIG="userpatches/config-default.conf"
fi

# source build configuration file
CONFIG_FILE="$(realpath "$CONFIG")"
if [[ ! -f $CONFIG_FILE ]]; then
	display_alert "Config file does not exist" "$CONFIG" "error"
	exit 254
fi

CONFIG_PATH=$(dirname "$CONFIG_FILE")

display_alert "Using config file" "$CONFIG_FILE" "info"
pushd $CONFIG_PATH > /dev/null
# shellcheck source=/dev/null
source "$CONFIG_FILE"
popd > /dev/null

[[ -z "${USERPATCHES_PATH}" ]] && USERPATCHES_PATH="$CONFIG_PATH"

if [[ $EUID != 0 ]]; then
	display_alert "This script requires root privileges, trying to use sudo" "" "wrn"
	sudo "$SRC/compile.sh" "$@"
	exit $?
fi

# Script parameters handling
for i in "$@"; do
	if [[ $i == *=* ]]; then
		parameter=${i%%=*}
		value=${i##*=}
		display_alert "Command line: setting $parameter to" "${value:-(empty)}" "info"
		eval "$parameter=\"$value\""
	fi
done

if [[ ! -f $SRC/.ignore_changes ]]; then
	echo -e "[\e[0;32m o.k. \x1B[0m] This script will try to update"
	git pull
	CHANGED_FILES=$(git diff --name-only)
	if [[ -n $CHANGED_FILES ]]; then
		echo -e "[\e[0;35m warn \x1B[0m] Can't update since you made changes to: \e[0;32m\n${CHANGED_FILES}\x1B[0m"
		while true; do
			echo -e "Press \e[0;33m<Ctrl-C>\x1B[0m or \e[0;33mexit\x1B[0m to abort compilation, \e[0;33m<Enter>\x1B[0m to ignore and continue, \e[0;33mdiff\x1B[0m to display changes"
			read -r
			if [[ "$REPLY" == "diff" ]]; then
				git diff
			elif [[ "$REPLY" == "exit" ]]; then
				exit 1
			elif [[ "$REPLY" == "" ]]; then
				break
			else
				echo "Unknown command!"
			fi
		done
	else
		git checkout "${LIB_TAG:-master}"
	fi
fi

if [[ $BUILD_ALL == yes || $BUILD_ALL == demo ]]; then
	# shellcheck source=lib/build-all-ng.sh
	source "${SRC}"/lib/build-all-ng.sh
else
	# shellcheck source=lib/main.sh
	source "${SRC}"/lib/main.sh
fi
