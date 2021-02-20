#!/bin/bash

# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Main program
#

if [[ $(basename "$0") == main.sh ]]; then

	echo "Please use compile.sh to start the build process"
	exit 255

fi

# default umask for root is 022 so parent directories won't be group writeable without this
# this is used instead of making the chmod in prepare_host() recursive
umask 002

# destination
DEST="${SRC}"/output

if [[ $BUILD_ALL != "yes" && -z $ROOT_FS_CREATE_ONLY ]]; then
	# override stty size
	[[ -n $COLUMNS ]] && stty cols $COLUMNS
	[[ -n $LINES ]] && stty rows $LINES
	TTY_X=$(($(stty size | awk '{print $2}')-6)) 			# determine terminal width
	TTY_Y=$(($(stty size | awk '{print $1}')-6)) 			# determine terminal height
fi

# We'll use this title on all menus
backtitle="Armbian building script, http://www.armbian.com | Author: Igor Pecovnik"

# if language not set, set to english
[[ -z $LANGUAGE ]] && export LANGUAGE="en_US:en"

# default console if not set
[[ -z $CONSOLE_CHAR ]] && export CONSOLE_CHAR="UTF-8"

# Load libraries
# shellcheck source=debootstrap.sh
source "${SRC}"/lib/debootstrap.sh 						# system specific install
# shellcheck source=image-helpers.sh
source "${SRC}"/lib/image-helpers.sh						# helpers for OS image building
# shellcheck source=distributions.sh
source "${SRC}"/lib/distributions.sh						# system specific install
# shellcheck source=desktop.sh
source "${SRC}"/lib/desktop.sh							# desktop specific install
# shellcheck source=compilation.sh
source "${SRC}"/lib/compilation.sh						# patching and compilation of kernel, uboot, ATF
# shellcheck source=compilation-prepare.sh
source "${SRC}"/lib/compilation-prepare.sh					# kernel plugins - 3rd party drivers that are not upstreamed. Like WG, AUFS, various Wifi
# shellcheck source=makeboarddeb.sh
source "${SRC}"/lib/makeboarddeb.sh						# create board support package
# shellcheck source=general.sh
source "${SRC}"/lib/general.sh							# general functions
# shellcheck source=chroot-buildpackages.sh
source "${SRC}"/lib/chroot-buildpackages.sh					# building packages in chroot

# compress and remove old logs
mkdir -p "${DEST}"/debug
(cd "${DEST}"/debug && tar -czf logs-"$(<timestamp)".tgz ./*.log) > /dev/null 2>&1
rm -f "${DEST}"/debug/*.log > /dev/null 2>&1
date +"%d_%m_%Y-%H_%M_%S" > "${DEST}"/debug/timestamp
# delete compressed logs older than 7 days
(cd "${DEST}"/debug && find . -name '*.tgz' -mtime +7 -delete) > /dev/null

if [[ $PROGRESS_DISPLAY == none ]]; then

	OUTPUT_VERYSILENT=yes

elif [[ $PROGRESS_DISPLAY == dialog ]]; then

	OUTPUT_DIALOG=yes

fi

if [[ $PROGRESS_LOG_TO_FILE != yes ]]; then unset PROGRESS_LOG_TO_FILE; fi

SHOW_WARNING=yes

if [[ $USE_CCACHE != no ]]; then

	CCACHE=ccache
	export PATH="/usr/lib/ccache:$PATH"
	# private ccache directory to avoid permission issues when using build script with "sudo"
	# see https://ccache.samba.org/manual.html#_sharing_a_cache for alternative solution
	[[ $PRIVATE_CCACHE == yes ]] && export CCACHE_DIR=$SRC/cache/ccache

else

	CCACHE=""

fi

if [[ -n $REPOSITORY_UPDATE ]]; then

        # select stable/beta configuration
        if [[ $BETA == yes ]]; then
                DEB_STORAGE=$DEST/debs-beta
                REPO_STORAGE=$DEST/repository-beta
                REPO_CONFIG="aptly-beta.conf"
        else
                DEB_STORAGE=$DEST/debs
                REPO_STORAGE=$DEST/repository
                REPO_CONFIG="aptly.conf"
        fi

        # For user override
        if [[ -f "${USERPATCHES_PATH}"/lib.config ]]; then
                display_alert "Using user configuration override" "userpatches/lib.config" "info"
            source "${USERPATCHES_PATH}"/lib.config
        fi

        repo-manipulate "$REPOSITORY_UPDATE"
        exit

fi

if [ "$OFFLINE_WORK" == "yes" ]; then
	echo -e "\n"
	display_alert "* " "You are working offline."
	display_alert "* " "Sources, time and host will not be checked"
	echo -e "\n"
	sleep 3s
else
	# we need dialog to display the menu in case not installed. Other stuff gets installed later
	prepare_host_basic
fi

# if KERNEL_ONLY, KERNEL_CONFIGURE, BOARD, BRANCH or RELEASE are not set, display selection menu

if [[ -z $KERNEL_ONLY ]]; then

	options+=("yes" "U-boot and kernel packages")
	options+=("no" "Full OS image for flashing")
	KERNEL_ONLY=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
	--menu "Select what to build" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $KERNEL_ONLY ]] && exit_with_error "No option selected"

fi

if [[ -z $KERNEL_CONFIGURE ]]; then

	options+=("no" "Do not change the kernel configuration")
	options+=("yes" "Show a kernel configuration menu before compilation")
	options+=("prebuilt" "Use precompiled packages from Armbian repository")
	KERNEL_CONFIGURE=$(dialog --stdout --title "Choose an option" --backtitle "$backtitle" --no-tags \
	--menu "Select the kernel configuration" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $KERNEL_CONFIGURE ]] && exit_with_error "No option selected"

fi

[[ ${KERNEL_CONFIGURE} == prebuilt ]] && REPOSITORY_INSTALL="u-boot,kernel,bsp,armbian-zsh,armbian-config,armbian-firmware"

if [[ -z $BOARD ]]; then

	WIP_STATE=supported
	WIP_BUTTON='CSC/WIP/EOS/TVB'
	STATE_DESCRIPTION=' - boards with high level of software maturity'
	temp_rc=$(mktemp)

	while true; do
		options=()
		if [[ $WIP_STATE == supported ]]; then

			for board in "${SRC}"/config/boards/*.conf; do
				options+=("$(basename "${board}" | cut -d'.' -f1)" "$(head -1 "${board}" | cut -d'#' -f2)")
			done

		else

			for board in "${SRC}"/config/boards/*.wip; do
				options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(WIP)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
			done
			for board in "${SRC}"/config/boards/*.csc; do
				options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(CSC)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
			done
			for board in "${SRC}"/config/boards/*.eos; do
				options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(EOS)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
			done
			for board in "${SRC}"/config/boards/*.tvb; do
				options+=("$(basename "${board}" | cut -d'.' -f1)" "\Z1(TVB)\Zn $(head -1 "${board}" | cut -d'#' -f2)")
			done

		fi

		if [[ $WIP_STATE != supported ]]; then
			cat <<-'EOF' > "${temp_rc}"
			dialog_color = (RED,WHITE,OFF)
			screen_color = (WHITE,RED,ON)
			tag_color = (RED,WHITE,ON)
			item_selected_color = (WHITE,RED,ON)
			tag_selected_color = (WHITE,RED,ON)
			tag_key_selected_color = (WHITE,RED,ON)
			EOF
		else
			echo > "${temp_rc}"
		fi
		BOARD=$(DIALOGRC=$temp_rc dialog --stdout --title "Choose a board" --backtitle "$backtitle" --scrollbar \
			--colors --extra-label "Show $WIP_BUTTON" --extra-button \
			--menu "Select the target board. Displaying:\n$STATE_DESCRIPTION" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		STATUS=$?
		if [[ $STATUS == 3 ]]; then
			if [[ $WIP_STATE == supported ]]; then

				[[ $SHOW_WARNING == yes ]] && show_developer_warning
				STATE_DESCRIPTION=' - \Z1(CSC)\Zn - Community Supported Configuration\n - \Z1(WIP)\Zn - Work In Progress
				\n - \Z1(EOS)\Zn - End Of Support\n - \Z1(TVB)\Zn - TV boxes'
				WIP_STATE=unsupported
				WIP_BUTTON='matured'
				EXPERT=yes

			else

				STATE_DESCRIPTION=' - boards with high level of software maturity'
				WIP_STATE=supported
				WIP_BUTTON='CSC/WIP/EOS'
				EXPERT=no

			fi
			continue
		elif [[ $STATUS == 0 ]]; then
			break
		fi
		unset options
		[[ -z $BOARD ]] && exit_with_error "No board selected"
	done
fi

if [[ -f $SRC/config/boards/${BOARD}.conf ]]; then
	BOARD_TYPE='conf'
elif [[ -f $SRC/config/boards/${BOARD}.csc ]]; then
	BOARD_TYPE='csc'
elif [[ -f $SRC/config/boards/${BOARD}.wip ]]; then
	BOARD_TYPE='wip'
elif [[ -f $SRC/config/boards/${BOARD}.eos ]]; then
	BOARD_TYPE='eos'
elif [[ -f $SRC/config/boards/${BOARD}.tvb ]]; then
	BOARD_TYPE='tvb'
fi

# shellcheck source=/dev/null
source "${SRC}/config/boards/${BOARD}.${BOARD_TYPE}"
LINUXFAMILY="${BOARDFAMILY}"

[[ -z $KERNEL_TARGET ]] && exit_with_error "Board configuration does not define valid kernel config"

if [[ -z $BRANCH ]]; then

	options=()
	[[ $KERNEL_TARGET == *current* ]] && options+=("current" "Recommended. Come with best support")
	[[ $KERNEL_TARGET == *legacy* ]] && options+=("legacy" "Old stable / Legacy")
	[[ $KERNEL_TARGET == *dev* && $EXPERT = yes ]] && options+=("dev" "\Z1Development version (@kernel.org)\Zn")

	# do not display selection dialog if only one kernel branch is available
	if [[ "${#options[@]}" == 2 ]]; then
		BRANCH="${options[0]}"
	else
		BRANCH=$(dialog --stdout --title "Choose a kernel" --backtitle "$backtitle" --colors \
			--menu "Select the target kernel branch\nExact kernel versions depend on selected board" \
			$TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
	fi
	unset options
	[[ -z $BRANCH ]] && exit_with_error "No kernel branch selected"
	[[ $BRANCH == dev && $SHOW_WARNING == yes ]] && show_developer_warning

else
	[[ $BRANCH == next ]] && KERNEL_TARGET="next"
	# next = new legacy. Should stay for backward compatibility, but be removed from menu above
	# or we left definitions in board configs and only remove menu
	[[ $KERNEL_TARGET != *$BRANCH* ]] && exit_with_error "Kernel branch not defined for this board" "$BRANCH"

fi

# define distribution support status
declare -A distro_name distro_support
distro_name['stretch']="Debian 9 Stretch"
distro_support['stretch']="eos"
distro_name['buster']="Debian 10 Buster"
distro_support['buster']="supported"
distro_name['bullseye']="Debian 11 Bullseye"
distro_support['bullseye']="csc"
distro_name['xenial']="Ubuntu Xenial 16.04 LTS"
distro_support['xenial']="eos"
distro_name['bionic']="Ubuntu Bionic 18.04 LTS"
distro_support['bionic']="supported"
distro_name['focal']="Ubuntu Focal 20.04 LTS"
distro_support['focal']="supported"
distro_name['groovy']="Ubuntu Groovy 20.10"
distro_support['groovy']="csc"

if [[ $KERNEL_ONLY != yes && -z $RELEASE ]]; then

	options=()

		distro_menu "focal"
		distro_menu "buster"
		distro_menu "bionic"
		distro_menu "bullseye"
		distro_menu "groovy"
		distro_menu "stretch"
		distro_menu "xenial"

		RELEASE=$(dialog --stdout --title "Choose a release package base" --backtitle "$backtitle" \
		--menu "Select the target OS release package base" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
		[[ -z $RELEASE ]] && exit_with_error "No release selected"

fi

# read distribution support status which is written to the armbian-release file
distro_menu "$RELEASE"
unset options

# don't show desktop option if we choose minimal build
[[ $BUILD_MINIMAL == yes ]] && BUILD_DESKTOP=no

if [[ $KERNEL_ONLY != yes && -z $BUILD_DESKTOP ]]; then

	options=()
	options+=("no" "Image with console interface (server)")
	options+=("yes" "Image with desktop environment")
	BUILD_DESKTOP=$(dialog --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
	--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $BUILD_DESKTOP ]] && exit_with_error "No option selected"
	[[ $BUILD_DESKTOP == yes ]] && BUILD_MINIMAL=no

fi

if [[ $KERNEL_ONLY != yes && $BUILD_DESKTOP == no && -z $BUILD_MINIMAL ]]; then

	options=()
	options+=("no" "Standard image with console interface")
	options+=("yes" "Minimal image with console interface")
	BUILD_MINIMAL=$(dialog --stdout --title "Choose image type" --backtitle "$backtitle" --no-tags \
	--menu "Select the target image type" $TTY_Y $TTY_X $((TTY_Y - 8)) "${options[@]}")
	unset options
	[[ -z $BUILD_MINIMAL ]] && exit_with_error "No option selected"

fi

# prevent conflicting setup
[[ $BUILD_DESKTOP == yes ]] && BUILD_MINIMAL=no
[[ $BUILD_MINIMAL == yes ]] && EXTERNAL=no

# ZFS support is limited
[[ $INCLUDE_ZFS == yes ]] && [[ $RELEASE != focal && $RELEASE != buster ]] && exit_with_error "ZFS build is only supported in Focal and Buster"

#shellcheck source=configuration.sh
source "${SRC}"/lib/configuration.sh

# optimize build time with 100% CPU usage
CPUS=$(grep -c 'processor' /proc/cpuinfo)
if [[ $USEALLCORES != no ]]; then

	CTHREADS="-j$((CPUS + CPUS/2))"

else

	CTHREADS="-j1"

fi

if [[ $BETA == yes ]]; then
	IMAGE_TYPE=nightly
elif [[ $BETA != "yes" && $BUILD_ALL == yes && -n $GPG_PASS ]]; then
	IMAGE_TYPE=stable
else
	IMAGE_TYPE=user-built
fi

branch2dir() {
	[[ "${1}" == "head" ]] && echo "HEAD" || echo "${1##*:}"
}

BOOTSOURCEDIR="${BOOTDIR}/$(branch2dir "${BOOTBRANCH}")"
LINUXSOURCEDIR="${KERNELDIR}/$(branch2dir "${KERNELBRANCH}")"
[[ -n $ATFSOURCE ]] && ATFSOURCEDIR="${ATFDIR}/$(branch2dir "${ATFBRANCH}")"

# define package names
DEB_BRANCH=${BRANCH//default}
# if not empty, append hyphen
DEB_BRANCH=${DEB_BRANCH:+${DEB_BRANCH}-}
CHOSEN_UBOOT=linux-u-boot-${DEB_BRANCH}${BOARD}
CHOSEN_KERNEL=linux-image-${DEB_BRANCH}${LINUXFAMILY}
CHOSEN_ROOTFS=linux-${RELEASE}-root-${DEB_BRANCH}${BOARD}
CHOSEN_DESKTOP=armbian-${RELEASE}-desktop
CHOSEN_KSRC=linux-source-${BRANCH}-${LINUXFAMILY}

do_default() {

start=$(date +%s)

# Check and install dependencies, directory structure and settings
# The OFFLINE_WORK variable inside the function
prepare_host

[[ $CLEAN_LEVEL == *sources* ]] && cleaning "sources"

# fetch_from_repo <url> <dir> <ref> <subdir_flag>

# ignore updates help on building all images - for internal purposes
if [[ $IGNORE_UPDATES != yes ]]; then
display_alert "Downloading sources" "" "info"

fetch_from_repo "$BOOTSOURCE" "$BOOTDIR" "$BOOTBRANCH" "yes"
fetch_from_repo "$KERNELSOURCE" "$KERNELDIR" "$KERNELBRANCH" "yes"
if [[ -n $ATFSOURCE ]]; then
	fetch_from_repo "$ATFSOURCE" "$ATFDIR" "$ATFBRANCH" "yes"
fi
fetch_from_repo "https://github.com/linux-sunxi/sunxi-tools" "sunxi-tools" "branch:master"
fetch_from_repo "https://github.com/armbian/rkbin" "rkbin-tools" "branch:master"
fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/A3700-utils-marvell" "marvell-tools" "branch:A3700_utils-armada-18.12"
fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/mv-ddr-marvell.git" "marvell-ddr" "branch:mv_ddr-armada-18.12"
fetch_from_repo "https://github.com/MarvellEmbeddedProcessors/binaries-marvell" "marvell-binaries" "branch:binaries-marvell-armada-18.12"
fetch_from_repo "https://github.com/armbian/odroidc2-blobs" "odroidc2-blobs" "branch:master"
fetch_from_repo "https://github.com/armbian/testings" "testing-reports" "branch:master"
fetch_from_repo "https://github.com/LibreELEC/amlogic-boot-fip" "amlogic-boot-fip" "branch:master"

compile_sunxi_tools
install_rkbin_tools

for option in $(tr ',' ' ' <<< "$CLEAN_LEVEL"); do
	[[ $option != sources ]] && cleaning "$option"
done

fi

# Compile u-boot if packed .deb does not exist or use the one from repository
if [[ ! -f "${DEB_STORAGE}"/${CHOSEN_UBOOT}_${REVISION}_${ARCH}.deb ]]; then

	if [[ -n "${ATFSOURCE}" && "${REPOSITORY_INSTALL}" != *u-boot* ]]; then
		compile_atf
	fi
	[[ "${REPOSITORY_INSTALL}" != *u-boot* ]] && compile_uboot

fi

# Compile kernel if packed .deb does not exist or use the one from repository
if [[ ! -f ${DEB_STORAGE}/${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb ]]; then

	KDEB_CHANGELOG_DIST=$RELEASE
	[[ "${REPOSITORY_INSTALL}" != *kernel* ]] && compile_kernel

fi

# Compile armbian-config if packed .deb does not exist or use the one from repository
if [[ ! -f ${DEB_STORAGE}/armbian-config_${REVISION}_all.deb ]]; then

	[[ "${REPOSITORY_INSTALL}" != *armbian-config* ]] && compile_armbian-config

fi

# Compile armbian-zsh if packed .deb does not exist or use the one from repository
if [[ ! -f ${DEB_STORAGE}/armbian-zsh_${REVISION}_all.deb ]]; then

        [[ "${REPOSITORY_INSTALL}" != *armbian-zsh* ]] && compile_armbian-zsh

fi

# Compile armbian-firmware if packed .deb does not exist or use the one from repository
if ! ls "${DEB_STORAGE}/armbian-firmware_${REVISION}_all.deb" 1> /dev/null 2>&1 || ! ls "${DEB_STORAGE}/armbian-firmware-full_${REVISION}_all.deb" 1> /dev/null 2>&1; then

	if [[ "${REPOSITORY_INSTALL}" != *armbian-firmware* ]]; then

		FULL=""
		REPLACE="-full"
		compile_firmware
		FULL="-full"
		REPLACE=""
		compile_firmware

	fi

fi

overlayfs_wrapper "cleanup"

# create board support package
[[ -n $RELEASE && ! -f ${DEB_STORAGE}/$RELEASE/${CHOSEN_ROOTFS}_${REVISION}_${ARCH}.deb ]] && create_board_package

# create desktop package
[[ -n $RELEASE && ! -f ${DEB_STORAGE}/$RELEASE/${CHOSEN_DESKTOP}_${REVISION}_all.deb ]] && create_desktop_package

# build additional packages
[[ $EXTERNAL_NEW == compile ]] && chroot_build_packages

if [[ $KERNEL_ONLY != yes ]]; then
	[[ $BSP_BUILD != yes ]] && debootstrap_ng
else
	display_alert "Kernel build done" "@host" "info"
	display_alert "Target directory" "${DEB_STORAGE}/" "info"
	display_alert "File name" "${CHOSEN_KERNEL}_${REVISION}_${ARCH}.deb" "info"
fi

# hook for function to run after build, i.e. to change owner of $SRC
# NOTE: this will run only if there were no errors during build process
[[ $(type -t run_after_build) == function ]] && run_after_build || true

end=$(date +%s)
runtime=$(((end-start)/60))
display_alert "Runtime" "$runtime min" "info"

# Make it easy to repeat build by displaying build options used
[ "$(systemd-detect-virt)" == 'docker' ] && BUILD_CONFIG='docker'
display_alert "Repeat Build Options" "./compile.sh ${BUILD_CONFIG} BOARD=${BOARD} BRANCH=${BRANCH} \
$([[ -n $RELEASE ]] && echo "RELEASE=${RELEASE} ")\
$([[ -n $BUILD_MINIMAL ]] && echo "BUILD_MINIMAL=${BUILD_MINIMAL} ")\
$([[ -n $BUILD_DESKTOP ]] && echo "BUILD_DESKTOP=${BUILD_DESKTOP} ")\
$([[ -n $KERNEL_ONLY ]] && echo "KERNEL_ONLY=${KERNEL_ONLY} ")\
$([[ -n $KERNEL_CONFIGURE ]] && echo "KERNEL_CONFIGURE=${KERNEL_CONFIGURE} ")\
$([[ -n $COMPRESS_OUTPUTIMAGE ]] && echo "COMPRESS_OUTPUTIMAGE=${COMPRESS_OUTPUTIMAGE} ")\
" "ext"

} # end of do_default()

if [[ -z $1 ]]; then
	do_default
else
	eval "$@"
fi
