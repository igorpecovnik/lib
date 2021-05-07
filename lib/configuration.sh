#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# common options
# daily beta build contains date in subrevision
#if [[ $BETA == yes && -z $SUBREVISION ]]; then SUBREVISION="."$(date --date="tomorrow" +"%j"); fi
REVISION=$(cat "${SRC}"/VERSION)"$SUBREVISION" # all boards have same revision
[[ -z $ROOTPWD ]] && ROOTPWD="1234" # Must be changed @first login
[[ -z $MAINTAINER ]] && MAINTAINER="Igor Pecovnik" # deb signature
[[ -z $MAINTAINERMAIL ]] && MAINTAINERMAIL="igor.pecovnik@****l.com" # deb signature
TZDATA=$(cat /etc/timezone) # Timezone for target is taken from host or defined here.
USEALLCORES=yes # Use all CPU cores for compiling
HOSTRELEASE=$(cat /etc/os-release | grep VERSION_CODENAME | cut -d"=" -f2)
[[ -z $EXIT_PATCHING_ERROR ]] && EXIT_PATCHING_ERROR="" # exit patching if failed
[[ -z $HOST ]] && HOST="$BOARD" # set hostname to the board
cd "${SRC}" || exit
ROOTFSCACHE_VERSION=5
CHROOT_CACHE_VERSION=7
BUILD_REPOSITORY_URL=$(improved_git remote get-url $(improved_git remote 2>/dev/null | grep origin) 2>/dev/null)
BUILD_REPOSITORY_COMMIT=$(improved_git describe --match=d_e_a_d_b_e_e_f --always --dirty 2>/dev/null)
ROOTFS_CACHE_MAX=200 # max number of rootfs cache, older ones will be cleaned up

if [[ $BETA == yes ]]; then
	DEB_STORAGE=$DEST/debs-beta
	REPO_STORAGE=$DEST/repository-beta
	REPO_CONFIG="aptly-beta.conf"
else
	DEB_STORAGE=$DEST/debs
	REPO_STORAGE=$DEST/repository
	REPO_CONFIG="aptly.conf"
fi

# TODO: fixed name can't be used for parallel image building
ROOT_MAPPER="armbian-root"

[[ -z $ROOTFS_TYPE ]] && ROOTFS_TYPE=ext4 # default rootfs type is ext4
[[ "ext4 f2fs btrfs xfs nfs fel" != *$ROOTFS_TYPE* ]] && exit_with_error "Unknown rootfs type" "$ROOTFS_TYPE"

[[ -z $BTRFS_COMPRESSION ]] && BTRFS_COMPRESSION=zlib # default btrfs filesystem compression method is zlib
[[ ! $BTRFS_COMPRESSION =~ zlib|lzo|zstd|none ]] && exit_with_error "Unknown btrfs compression method" "$BTRFS_COMPRESSION"

# Fixed image size is in 1M dd blocks (MiB)
# to get size of block device /dev/sdX execute as root:
# echo $(( $(blockdev --getsize64 /dev/sdX) / 1024 / 1024 ))
[[ "f2fs" == *$ROOTFS_TYPE* && -z $FIXED_IMAGE_SIZE ]] && exit_with_error "Please define FIXED_IMAGE_SIZE"

# a passphrase is mandatory if rootfs encryption is enabled
if [[ $CRYPTROOT_ENABLE == yes && -z $CRYPTROOT_PASSPHRASE ]]; then
	exit_with_error "Root encryption is enabled but CRYPTROOT_PASSPHRASE is not set"
fi

# small SD card with kernel, boot script and .dtb/.bin files
[[ $ROOTFS_TYPE == nfs ]] && FIXED_IMAGE_SIZE=64

# used by multiple sources - reduce code duplication
[[ $USE_MAINLINE_GOOGLE_MIRROR == yes ]] && MAINLINE_MIRROR=google

case $MAINLINE_MIRROR in
	google)
		MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'
		MAINLINE_FIRMWARE_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
		;;
	tuna)
		MAINLINE_KERNEL_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='https://mirrors.tuna.tsinghua.edu.cn/git/linux-firmware.git'
		;;
	bfsu)
		MAINLINE_KERNEL_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='https://mirrors.bfsu.edu.cn/git/linux-firmware.git'
		;;
	*)
		MAINLINE_KERNEL_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git'
		MAINLINE_FIRMWARE_SOURCE='git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git'
		;;
esac

MAINLINE_KERNEL_DIR='linux-mainline'

if [[ $USE_GITHUB_UBOOT_MIRROR == yes ]]; then
	MAINLINE_UBOOT_SOURCE='https://github.com/RobertCNelson/u-boot'
else
	MAINLINE_UBOOT_SOURCE='https://source.denx.de/u-boot/u-boot.git'
fi
MAINLINE_UBOOT_DIR='u-boot'

# Let's set default data if not defined in board configuration above
[[ -z $OFFSET ]] && OFFSET=4 # offset to 1st partition (we use 4MiB boundaries by default)
ARCH=armhf
KERNEL_IMAGE_TYPE=zImage
CAN_BUILD_STRETCH=yes
ATF_COMPILE=yes
[[ -z $CRYPTROOT_SSH_UNLOCK ]] && CRYPTROOT_SSH_UNLOCK=yes
[[ -z $CRYPTROOT_SSH_UNLOCK_PORT ]] && CRYPTROOT_SSH_UNLOCK_PORT=2022
# Default to pdkdf2, this used to be the default with cryptroot <= 2.0, however
# cryptroot 2.1 changed that to Argon2i. Argon2i is a memory intensive
# algorithm which doesn't play well with SBCs (need 1GiB RAM by default !)
# https://gitlab.com/cryptsetup/cryptsetup/-/issues/372
[[ -z $CRYPTROOT_PARAMETERS ]] && CRYPTROOT_PARAMETERS="--pbkdf pbkdf2"
[[ -z $WIREGUARD ]] && WIREGUARD="yes"
[[ -z $EXTRAWIFI ]] && EXTRAWIFI="yes"
[[ -z $AUFS ]] && AUFS="yes"
[[ -z $IMAGE_PARTITION_TABLE ]] && IMAGE_PARTITION_TABLE="msdos"

# single ext4 partition is the default and preferred configuration
#BOOTFS_TYPE=''
[[ ! -f ${SRC}/config/sources/families/$LINUXFAMILY.conf ]] && \
	exit_with_error "Sources configuration not found" "$LINUXFAMILY"

source "${SRC}/config/sources/families/${LINUXFAMILY}.conf"

if [[ -f $USERPATCHES_PATH/sources/families/$LINUXFAMILY.conf ]]; then
	display_alert "Adding user provided $LINUXFAMILY overrides"
	source "$USERPATCHES_PATH/sources/families/${LINUXFAMILY}.conf"
fi

# load architecture defaults
source "${SRC}/config/sources/${ARCH}.conf"

## Fragments: at this point we've sourced all the config files that will be used,
##            and (hopefully) not yet invoked any hook points. So this is the perfect
##            place to initialize the fragment manager. It will create functions
##            like the 'post_family_config' that is invoked below.
initialize_fragment_manager

call_hook_point "post_family_config" "config_tweaks_post_family_config" << 'POST_FAMILY_CONFIG'
*give the config a chance to override the family/arch defaults*
This hook is called after the family configuration (`sources/families/xxx.conf`) is sourced.
Since the family can override values from the user configuration and the board configuration,
it is often used to in turn override those.
POST_FAMILY_CONFIG

# Myy : Menu configuration for choosing desktop configurations

show_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	# Myy : I don't know why there's a TTY_Y - 8...
	#echo "Provided title : $provided_title"
	#echo "Provided backtitle : $provided_backtitle"
	#echo "Provided menuname : $provided_menuname"
	#echo "Provided options : " "${@:4}"
	#echo "TTY X: $TTY_X Y: $TTY_Y"
	dialog --stdout --title "$provided_title" --backtitle "${provided_backtitle}" \
	--menu "$provided_menuname" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
}

# Myy : FIXME Factorize
show_select_menu() {
	provided_title=$1
	provided_backtitle=$2
	provided_menuname=$3
	dialog --stdout --title "${provided_title}" --backtitle "${provided_backtitle}" \
	--checklist "${provided_menuname}" $TTY_Y $TTY_X $((TTY_Y - 8)) "${@:4}"
}

# Myy : Once we got a list of selected groups, parse the PACKAGE_LIST inside configuration.sh

DESKTOP_ELEMENTS_DIR="${SRC}/config/desktop/${RELEASE}"
DESKTOP_CONFIGS_DIR="${DESKTOP_ELEMENTS_DIR}/environments"
DESKTOP_CONFIG_PREFIX="config_"
DESKTOP_APPGROUPS_DIR="${DESKTOP_ELEMENTS_DIR}/appgroups"

desktop_element_available_for_arch() {
	local desktop_element_path="${1}"
	local targeted_arch="${2}"

	local arch_limitation_file="${1}/only_for"

	echo "Checking if ${desktop_element_path} is available for ${targeted_arch} in ${arch_limitation_file}" >> "${DEST}"/debug/output.log
	if [[ -f "${arch_limitation_file}" ]]; then
		grep -- "${targeted_arch}" "${arch_limitation_file}"
		return $?
	else
		return 0
	fi
}

desktop_element_supported() {

	local desktop_element_path="${1}"

	local support_level_filepath="${desktop_element_path}/support"
	if [[ -f "${support_level_filepath}" ]]; then
		local support_level="$(cat "${support_level_filepath}")"
		if [[ "${support_level}" != "supported" && "${EXPERT}" != "yes" ]]; then
			return 65
		fi

		desktop_element_available_for_arch "${desktop_element_path}" "${ARCH}"
		if [[ $? -ne 0 ]]; then
			return 66
		fi
	else
		return 64
	fi

	return 0

}

if [[ $BUILD_DESKTOP == "yes" && -z $DESKTOP_ENVIRONMENT ]]; then

	desktop_environments_prepare_menu() {
		for desktop_env_dir in "${DESKTOP_CONFIGS_DIR}/"*; do
			local desktop_env_name=$(basename ${desktop_env_dir})
			local expert_infos=""
			[[ "${EXPERT}" == "yes" ]] && expert_infos="[$(cat "${desktop_env_dir}/support" 2> /dev/null)]"
			desktop_element_supported "${desktop_env_dir}" "${ARCH}" && options+=("${desktop_env_name}" "${desktop_env_name^} desktop environment ${expert_infos}")
		done
	}

	options=()
	desktop_environments_prepare_menu

	if [[ "${options[0]}" == "" ]]; then
		exit_with_error "No desktop environment seems to be available for your board ${BOARD} (ARCH : ${ARCH} - EXPERT : ${EXPERT})"
	fi

	DESKTOP_ENVIRONMENT=$(show_menu "Choose a desktop environment" "$backtitle" "Select the default desktop environment to bundle with this image" "${options[@]}")

	unset options

	if [[ -z "${DESKTOP_ENVIRONMENT}" ]]; then
		exit_with_error "No desktop environment selected..."
	fi

fi

if [[ $BUILD_DESKTOP == "yes" ]]; then
	# Expected environment variables :
	# - options
	# - ARCH

	desktop_environment_check_if_valid() {

		local error_msg=""
		desktop_element_supported "${DESKTOP_ENVIRONMENT_DIRPATH}" "${ARCH}"
		local retval=$?

		if [[ ${retval} == 0 ]]; then
			return
		elif [[ ${retval} == 64 ]]; then
			error_msg+="Either the desktop environment ${DESKTOP_ENVIRONMENT} does not exist "
			error_msg+="or the file ${DESKTOP_ENVIRONMENT_DIRPATH}/support is missing"
		elif [[ ${retval} == 65 ]]; then
			error_msg+="Only experts can build an image with the desktop environment \"${DESKTOP_ENVIRONMENT}\", since the Armbian team won't offer any support for it (EXPERT=${EXPERT})"
		elif [[ ${retval} == 66 ]]; then
			error_msg+="The desktop environment \"${DESKTOP_ENVIRONMENT}\" has no packages for your targeted board architecture (BOARD=${BOARD} ARCH=${ARCH}). "
			error_msg+="The supported boards architectures are : "
			error_msg+="$(cat "${DESKTOP_ENVIRONMENT_DIRPATH}/only_for")"
		fi

		# supress error when cache is rebuilding
		[[ -n "$ROOT_FS_CREATE_ONLY" ]] && exit 0

		exit_with_error "${error_msg}"
	}

	DESKTOP_ENVIRONMENT_DIRPATH="${DESKTOP_CONFIGS_DIR}/${DESKTOP_ENVIRONMENT}"

	desktop_environment_check_if_valid
fi

if [[ $BUILD_DESKTOP == "yes" && -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
	# FIXME Check for empty folders, just in case the current maintainer
	# messed up
	# Note, we could also ignore it and don't show anything in the previous
	# menu, but that hides information and make debugging harder, which I
	# don't like. Adding desktop environments as a maintainer is not a
	# trivial nor common task.

	options=()
	for configuration in "${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_CONFIG_PREFIX}"*; do
		config_filename=$(basename ${configuration})
		config_name=${config_filename#"${DESKTOP_CONFIG_PREFIX}"}
		options+=("${config_filename}" "${config_name} configuration")
	done

	DESKTOP_ENVIRONMENT_CONFIG_NAME=$(show_menu "Choose the desktop environment config" "$backtitle" "Select the configuration for this environment.\nThese are sourced from ${desktop_environment_config_dir}" "${options[@]}")
	unset options

	if [[ -z $DESKTOP_ENVIRONMENT_CONFIG_NAME ]]; then
		exit_with_error "No desktop configuration selected... Do you really want a desktop environment ?"
	fi
fi

if [[ $BUILD_DESKTOP == "yes" ]]; then
	DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH="${DESKTOP_ENVIRONMENT_DIRPATH}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}"
	DESKTOP_ENVIRONMENT_PACKAGE_LIST_FILEPATH="${DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH}/packages"
fi

# "-z ${VAR+x}" allows to check for unset variable
# Technically, someone might want to build a desktop with no additional
# appgroups.
if [[ $BUILD_DESKTOP == "yes" && -z ${DESKTOP_APPGROUPS_SELECTED+x} ]]; then

	options=()
	for appgroup_path in "${DESKTOP_APPGROUPS_DIR}/"*; do
		appgroup="$(basename "${appgroup_path}")"
		options+=("${appgroup}" "${appgroup^}" off)
	done

	DESKTOP_APPGROUPS_SELECTED=$(\
		show_select_menu \
		"Choose desktop softwares to add" \
		"$backtitle" \
		"Select which kind of softwares you'd like to add to your build" \
		"${options[@]}")

	unset options
fi

#exit_with_error 'Testing'

# Expected variables
# - aggregated_content
# - potential_paths
# - separator
# Write to variables :
# - aggregated_content
aggregate_content() {
	echo -e "Potential paths : ${potential_paths}" >> "${DEST}"/debug/output.log
	for filepath in ${potential_paths}; do
		if [[ -f "${filepath}" ]]; then
			echo -e "${filepath/"$SRC"\//} yes" >> "${DEST}"/debug/output.log
			aggregated_content+=$(cat "${filepath}")
			aggregated_content+="${separator}"
#		else
#			echo -e "${filepath/"$SRC"\//} no\n" >> "${DEST}"/debug/output.log
		fi

	done
	echo "" >> "${DEST}"/debug/output.log
}

# set unique mounting directory
MOUNT_UUID=$(uuidgen)
SDCARD="${SRC}/.tmp/rootfs-${MOUNT_UUID}"
MOUNT="${SRC}/.tmp/mount-${MOUNT_UUID}"
DESTIMG="${SRC}/.tmp/image-${MOUNT_UUID}"

# dropbear needs to be configured differently
[[ $CRYPTROOT_ENABLE == yes && $RELEASE == xenial ]] && exit_with_error "Encrypted rootfs is not supported in Xenial"
[[ $RELEASE == stretch && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Debian Stretch images with selected kernel is not supported"
[[ $RELEASE == bionic && $CAN_BUILD_STRETCH != yes ]] && exit_with_error "Building Ubuntu Bionic images with selected kernel is not supported"
[[ $RELEASE == hirsute && $HOSTRELEASE == focal ]] && exit_with_error "Building Ubuntu Hirsute images requires Hirsute build host. Please upgrade your host or select a different target OS"

[[ -n $ATFSOURCE && -z $ATF_USE_GCC ]] && exit_with_error "Error in configuration: ATF_USE_GCC is unset"
[[ -z $UBOOT_USE_GCC ]] && exit_with_error "Error in configuration: UBOOT_USE_GCC is unset"
[[ -z $KERNEL_USE_GCC ]] && exit_with_error "Error in configuration: KERNEL_USE_GCC is unset"

BOOTCONFIG_VAR_NAME=BOOTCONFIG_${BRANCH^^}
[[ -n ${!BOOTCONFIG_VAR_NAME} ]] && BOOTCONFIG=${!BOOTCONFIG_VAR_NAME}
[[ -z $LINUXCONFIG ]] && LINUXCONFIG="linux-${LINUXFAMILY}-${BRANCH}"
[[ -z $BOOTPATCHDIR ]] && BOOTPATCHDIR="u-boot-$LINUXFAMILY"
[[ -z $ATFPATCHDIR ]] && ATFPATCHDIR="atf-$LINUXFAMILY"
[[ -z $KERNELPATCHDIR ]] && KERNELPATCHDIR="$LINUXFAMILY-$BRANCH"

if [[ "$RELEASE" =~ ^(xenial|bionic|focal|groovy|hirsute)$ ]]; then
		DISTRIBUTION="Ubuntu"
	else
		DISTRIBUTION="Debian"
fi

CLI_CONFIG_PATH="${SRC}/config/cli/${RELEASE}"
DEBOOTSTRAP_CONFIG_PATH="${CLI_CONFIG_PATH}/debootstrap"

if [[ $? != 0 ]]; then
	exit_with_error "The desktop environment ${DESKTOP_ENVIRONMENT} is not available for your architecture ${ARCH}"
fi

AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS="
${SRC}/config
${SRC}/config/optional/_any_board/_configs
${SRC}/config/optional/architectures/${ARCH}/_config
${SRC}/config/optional/families/${LINUXFAMILY}/_config
${SRC}/config/optional/boards/${BOARD}/_config
${USERPATCHES_PATH}
"

DEBOOTSTRAP_SEARCH_RELATIVE_DIRS="
cli/_all_distributions/debootstrap
cli/${RELEASE}/debootstrap
"

CLI_SEARCH_RELATIVE_DIRS="
cli/_all_distributions/main
cli/${RELEASE}/main
"

DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS="
desktop/_all_distributions/environments/_all_environments
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
desktop/${RELEASE}/environments/_all_environments
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/${DESKTOP_ENVIRONMENT_CONFIG_NAME}
"

DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS="
desktop/_all_distributions/appgroups
desktop/_all_distributions/environments/${DESKTOP_ENVIRONMENT}/appgroups
desktop/${RELEASE}/appgroups
desktop/${RELEASE}/environments/${DESKTOP_ENVIRONMENT}/appgroups
"

get_all_potential_paths() {
	local root_dirs="${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}"
	local rel_dirs="${1}"
	local sub_dirs="${2}"
	local looked_up_subpath="${3}"
	for root_dir in ${root_dirs}; do
		for rel_dir in ${rel_dirs}; do
			for sub_dir in ${sub_dirs}; do
				potential_paths+="${root_dir}/${rel_dir}/${sub_dir}/${looked_up_subpath} "
			done
		done
	done
	# for ppath in ${potential_paths}; do
	#  	echo "Checking for ${ppath}"
	#  	if [[ -f "${ppath}" ]]; then
	#  		echo "OK !|"
	#  	else
	#  		echo "Nope|"
	#  	fi
	# done
}

# Environment variables expected :
# - aggregated_content
# Arguments :
# 1. File to look up in each directory
# 2. The separator to add between each concatenated file
# 3. Relative directories paths added to ${3}
# 4. Relative directories paths added to ${4}
#
# The function will basically generate a list of potential paths by
# generating all the potential paths combinations leading to the
# looked up file
# ${AGGREGATION_SEARCH_ROOT_ABSOLUTE_DIRS}/${3}/${4}/${1}
# Then it will concatenate the content of all the available files
# into ${aggregated_content}
#
# TODO :
# ${4} could be removed by just adding the appropriate paths to ${3}
# dynamically for each case
# (debootstrap, cli, desktop environments, desktop appgroups, ...)

aggregate_all_root_rel_sub() {
	local separator="${2}"

	local potential_paths=""
	get_all_potential_paths "${3}" "${4}" "${1}"

	aggregate_content
}

aggregate_all_debootstrap() {
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	aggregate_all_root_rel_sub "${1}" "${2}" "${DEBOOTSTRAP_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

aggregate_all_cli() {
	local sub_dirs_to_check=". "
	if [[ ! -z "${SELECTED_CONFIGURATION+x}" ]]; then
		sub_dirs_to_check+="config_${SELECTED_CONFIGURATION}"
	fi
	aggregate_all_root_rel_sub "${1}" "${2}" "${CLI_SEARCH_RELATIVE_DIRS}" "${sub_dirs_to_check}"
}

aggregate_all_desktop() {
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_ENVIRONMENTS_SEARCH_RELATIVE_DIRS}" "."
	aggregate_all_root_rel_sub "${1}" "${2}" "${DESKTOP_APPGROUPS_SEARCH_RELATIVE_DIRS}" "${DESKTOP_APPGROUPS_SELECTED}"
}

one_line() {
	local aggregate_func_name="${1}"
	local aggregated_content=""
	shift 1
	$aggregate_func_name "${@}"
	cleanup_list aggregated_content
}

DEBOOTSTRAP_LIST="$(one_line aggregate_all_debootstrap "packages" " ")"
DEBOOTSTRAP_COMPONENTS="$(one_line aggregate_all_debootstrap "components" " ")"
DEBOOTSTRAP_COMPONENTS="${DEBOOTSTRAP_COMPONENTS// /,}"
PACKAGE_LIST="$(one_line aggregate_all_cli "packages" " ")"
PACKAGE_LIST_ADDITIONAL="$(one_line aggregate_all_cli "packages.additional" " ")"

echo "DEBOOTSTRAP LIST : ${DEBOOTSTRAP_LIST}" >> "${DEST}"/debug/output.log
echo "DEBOOTSTRAP_COMPONENTS : ${DEBOOTSTRAP_COMPONENTS}" >> "${DEST}"/debug/output.log
echo "CLI PACKAGE_LIST : ${PACKAGE_LIST}" >> "${DEST}"/debug/output.log
echo "CLI PACKAGE_LIST_ADDITIONAL : ${PACKAGE_LIST_ADDITIONAL}" >> "${DEST}"/debug/output.log

# Dependent desktop packages
# Myy : Sources packages from file here

# Myy : FIXME Rename aggregate_all to aggregate_all_desktop
if [[ $BUILD_DESKTOP == "yes" ]]; then
	PACKAGE_LIST_DESKTOP+="$(one_line aggregate_all_desktop "packages" " ")"
	echo "Groups selected ${DESKTOP_APPGROUPS_SELECTED} -> PACKAGES : ${PACKAGE_LIST_DESKTOP}" >> "${DEST}"/debug/output.log
fi

display_alert "Deboostrap" >> "${DEST}"/debug/output.log
display_alert "Components ${DEBOOTSTRAP_COMPONENTS}" >> "${DEST}"/debug/output.log
display_alert "Packages ${DEBOOTSTRAP_LIST}" >> "${DEST}"/debug/output.log
display_alert "----" >> "${DEST}"/debug/output.log
display_alert "CLI packages" >> "${DEST}"/debug/output.log
display_alert "Standard : ${PACKAGE_LIST}" >> "${DEST}"/debug/output.log
display_alert "Additional : ${PACKAGE_LIST_ADDITIONAL}" >> "${DEST}"/debug/output.log

DEBIAN_MIRROR='deb.debian.org/debian'
DEBIAN_SECURTY='security.debian.org/'
UBUNTU_MIRROR='ports.ubuntu.com/'

if [[ $DOWNLOAD_MIRROR == "china" ]] ; then
	DEBIAN_MIRROR='mirrors.tuna.tsinghua.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.tuna.tsinghua.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/'
fi

if [[ $DOWNLOAD_MIRROR == "bfsu" ]] ; then
	DEBIAN_MIRROR='mirrors.bfsu.edu.cn/debian'
	DEBIAN_SECURTY='mirrors.bfsu.edu.cn/debian-security'
	UBUNTU_MIRROR='mirrors.bfsu.edu.cn/ubuntu-ports/'
fi

# don't use mirrors that throws garbage on 404
if [[ -z ${ARMBIAN_MIRROR} ]]; then
	while true; do

		ARMBIAN_MIRROR=$(wget -SO- -T 1 -t 1 https://redirect.armbian.com 2>&1 | egrep -i "Location" | awk '{print $2}' | head -1)
		[[ ${ARMBIAN_MIRROR} != *armbian.hosthatch* ]] && break

	done
fi

# For (late) user override.
# Notice: it is too late to define hook functions or add fragments in lib.config, since the fragment initialization already ran by now.
#         in case the user tries to use them in lib.config, hopefully they'll be detected as "wishful hooking" and the user will be wrn'ed.
if [[ -f $USERPATCHES_PATH/lib.config ]]; then
	display_alert "Using user configuration override" "$USERPATCHES_PATH/lib.config" "info"
	source "$USERPATCHES_PATH"/lib.config
fi

call_hook_point "user_config" << 'USER_CONFIG'
*Invoke function with user override*
Allows for overriding configuration values set anywhere else.
It is called after sourcing the `lib.config` file if it exists,
but before assembling any package lists.
USER_CONFIG

# apt-cacher-ng mirror configurarion
if [[ $DISTRIBUTION == Ubuntu ]]; then
	APT_MIRROR=$UBUNTU_MIRROR
else
	APT_MIRROR=$DEBIAN_MIRROR
fi

[[ -n $APT_PROXY_ADDR ]] && display_alert "Using custom apt-cacher-ng address" "$APT_PROXY_ADDR" "info"

# Build final package list after possible override
PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_RELEASE $PACKAGE_LIST_ADDITIONAL"
PACKAGE_MAIN_LIST="$(cleanup_list PACKAGE_LIST)"

[[ $BUILD_DESKTOP == yes ]] && PACKAGE_LIST="$PACKAGE_LIST $PACKAGE_LIST_DESKTOP"
PACKAGE_LIST="$(cleanup_list PACKAGE_LIST)"

# remove any packages defined in PACKAGE_LIST_RM in lib.config
aggregated_content="${PACKAGE_LIST_RM} "
aggregate_all_cli "packages.remove" " "
aggregate_all_desktop "packages.remove" " "
PACKAGE_LIST_RM="$(cleanup_list aggregated_content)"
unset aggregated_content

aggregated_content=""
aggregate_all_cli "packages.uninstall" " "
aggregate_all_desktop "packages.uninstall" " "
PACKAGE_LIST_UNINSTALL="$(cleanup_list aggregated_content)"
unset aggregated_content

display_alert "PACKAGE_MAIN_LIST : ${PACKAGE_MAIN_LIST}" >> "${DEST}"/debug/output.log
display_alert "PACKAGE_LIST : ${PACKAGE_LIST}" >> "${DEST}"/debug/output.log
display_alert "PACKAGE_LIST_RM : ${PACKAGE_LIST_RM}" >> "${DEST}"/debug/output.log
display_alert "PACKAGE_LIST_UNINSTALL : ${PACKAGE_LIST_UNINSTALL}" >> "${DEST}"/debug/output.log

if [[ -n $PACKAGE_LIST_RM ]]; then
	display_alert "Remove filter : $(tr ' ' '|' <<< ${PACKAGE_LIST_RM})"
	# Turns out that \b can be tricked by dashes.
	# So if you remove mesa-utils but still want to install "mesa-utils-extra"
	# a "\b(mesa-utils)\b" filter will convert "mesa-utils-extra" to "-extra".
	# \W is not tricked by this but consumes the surrounding spaces, so we
	# replace the occurence by one space, to avoid sticking the next word to
	# the previous one after consuming the spaces.
	PACKAGE_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST} ")
	PACKAGE_MAIN_LIST=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_MAIN_LIST} ")
	if [[ $BUILD_DESKTOP == "yes" ]]; then
		PACKAGE_LIST_DESKTOP=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${PACKAGE_LIST_DESKTOP} ")
		# Removing double spaces... AGAIN, since we might have used a sed on them
		# Do not quote the variables. This would defeat the trick.
		PACKAGE_LIST_DESKTOP="$(echo ${PACKAGE_LIST_DESKTOP})"
	fi

	# Removing double spaces... AGAIN, since we might have used a sed on them
	# Do not quote the variables. This would defeat the trick.
	PACKAGE_LIST="$(echo ${PACKAGE_LIST})"
	PACKAGE_MAIN_LIST="$(echo ${PACKAGE_MAIN_LIST})"
fi

display_alert "After removal of packages.remove packages" >> "${DEST}"/debug/output.log
display_alert "PACKAGE_MAIN_LIST : \"${PACKAGE_MAIN_LIST}\"" >> "${DEST}"/debug/output.log
display_alert "PACKAGE_LIST : \"${PACKAGE_LIST}\"" >> "${DEST}"/debug/output.log

# Give the option to configure DNS server used in the chroot during the build process
[[ -z $NAMESERVER ]] && NAMESERVER="1.0.0.1" # default is cloudflare alternate

call_hook_point "post_aggregate_packages" "user_config_post_aggregate_packages" << 'POST_AGGREGATE_PACKAGES'
*For final user override, using a function, after all aggregations are done*
Called after aggregating all package lists, before the end of `compilation.sh`.
Packages will still be installed after this is called, so it is the last chance
to confirm or change any packages.
POST_AGGREGATE_PACKAGES

# debug
cat <<-EOF >> "${DEST}"/debug/output.log

## BUILD SCRIPT ENVIRONMENT

Repository: $REPOSITORY_URL
Version: $REPOSITORY_COMMIT

Host OS: $HOSTRELEASE
Host arch: $(dpkg --print-architecture)
Host system: $(uname -a)
Virtualization type: $(systemd-detect-virt)

## Build script directories
Build directory is located on:
$(findmnt -o TARGET,SOURCE,FSTYPE,AVAIL -T "${SRC}")

Build directory permissions:
$(getfacl -p "${SRC}")

Temp directory permissions:
$(getfacl -p "${SRC}"/.tmp 2> /dev/null)

## BUILD CONFIGURATION

Build target:
Board: $BOARD
Branch: $BRANCH
Minimal: $BUILD_MINIMAL
Desktop: $BUILD_DESKTOP
Desktop Environment: $DESKTOP_ENVIRONMENT
Software groups: $DESKTOP_APPGROUPS_SELECTED

Kernel configuration:
Repository: $KERNELSOURCE
Branch: $KERNELBRANCH
Config file: $LINUXCONFIG

U-boot configuration:
Repository: $BOOTSOURCE
Branch: $BOOTBRANCH
Config file: $BOOTCONFIG

Partitioning configuration:
Root partition type: $ROOTFS_TYPE
Boot partition type: ${BOOTFS_TYPE:-(none)}
User provided boot partition size: ${BOOTSIZE:-0}
Offset: $OFFSET

CPU configuration:
$CPUMIN - $CPUMAX with $GOVERNOR
EOF
