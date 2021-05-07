#!/bin/bash
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# mount_chroot
# umount_chroot
# unmount_on_exit
# check_loop_device
# install_external_applications
# write_uboot
# customize_image
# install_deb_chroot

# mount_chroot <target>
#
# helper to reduce code duplication
#
mount_chroot()
{
	local target=$1
	mount -t proc chproc "${target}"/proc
	mount -t sysfs chsys "${target}"/sys
	mount -t devtmpfs chdev "${target}"/dev || mount --bind /dev "${target}"/dev
	mount -t devpts chpts "${target}"/dev/pts
} #############################################################################

# umount_chroot <target>
#
# helper to reduce code duplication
#
umount_chroot()
{
	local target=$1
	display_alert "Unmounting" "$target" "info"
	while grep -Eq "${target}.*(dev|proc|sys)" /proc/mounts
	do
		umount -l --recursive "${target}"/dev >/dev/null 2>&1
		umount -l "${target}"/proc >/dev/null 2>&1
		umount -l "${target}"/sys >/dev/null 2>&1
		sleep 5
	done
} #############################################################################

# unmount_on_exit
#
unmount_on_exit()
{
	trap - INT TERM EXIT
	umount_chroot "${SDCARD}/"
	umount -l "${SDCARD}"/tmp >/dev/null 2>&1
	umount -l "${SDCARD}" >/dev/null 2>&1
	umount -l "${MOUNT}"/boot >/dev/null 2>&1
	umount -l "${MOUNT}" >/dev/null 2>&1
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose "${ROOT_MAPPER}"
	losetup -d "${LOOP}" >/dev/null 2>&1
	rm -rf --one-file-system "${SDCARD}"
	exit_with_error "debootstrap-ng was interrupted"
} #############################################################################

# check_loop_device <device_node>
#
check_loop_device()
{
	local device=$1
	if [[ ! -b $device ]]; then
		if [[ $CONTAINER_COMPAT == yes && -b /tmp/$device ]]; then
			display_alert "Creating device node" "$device"
			mknod -m0660 "${device}" b "0x$(stat -c '%t' "/tmp/$device")" "0x$(stat -c '%T' "/tmp/$device")"
		else
			exit_with_error "Device node $device does not exist"
		fi
	fi
} #############################################################################

# write_uboot <loopdev>
#
# writes u-boot to loop device
# Parameters:
# loopdev: loop device with mounted rootfs image
#
write_uboot()
{
	local loop=$1 revision
	display_alert "Writing U-boot bootloader" "$loop" "info"
	TEMP_DIR=$(mktemp -d || exit 1)
	chmod 700 ${TEMP_DIR}
	revision=${REVISION}
	if [[ -n $UPSTREM_VER ]]; then
		revision=${UPSTREM_VER}
		dpkg -x "${DEB_STORAGE}/linux-u-boot-${BOARD}-${BRANCH}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	else
		dpkg -x "${DEB_STORAGE}/${CHOSEN_UBOOT}_${revision}_${ARCH}.deb" ${TEMP_DIR}/
	fi
	write_uboot_platform "${TEMP_DIR}/usr/lib/${CHOSEN_UBOOT}_${revision}_${ARCH}" "$loop"
	[[ $? -ne 0 ]] && exit_with_error "U-boot bootloader failed to install" "@host"
	rm -rf ${TEMP_DIR}
} #############################################################################

customize_image()
{
	# for users that need to prepare files at host
	[[ -f $USERPATCHES_PATH/customize-image-host.sh ]] && source "$USERPATCHES_PATH"/customize-image-host.sh

	call_hook_point "pre_customize_image" "image_tweaks_pre_customize" << 'PRE_CUSTOMIZE_IMAGE'
*run before customize-image.sh*
This hook is called after `customize-image-host.sh` is called, but before the overlay is mounted.
It thus can be used for the same purposes as `customize-image-host.sh`.
PRE_CUSTOMIZE_IMAGE

	cp "$USERPATCHES_PATH"/customize-image.sh "${SDCARD}"/tmp/customize-image.sh
	chmod +x "${SDCARD}"/tmp/customize-image.sh
	mkdir -p "${SDCARD}"/tmp/overlay
	# util-linux >= 2.27 required
	mount -o bind,ro "$USERPATCHES_PATH"/overlay "${SDCARD}"/tmp/overlay
	display_alert "Calling image customization script" "customize-image.sh" "info"
	chroot "${SDCARD}" /bin/bash -c "/tmp/customize-image.sh $RELEASE $LINUXFAMILY $BOARD $BUILD_DESKTOP $ARCH"
	CUSTOMIZE_IMAGE_RC=$?
	umount -i "${SDCARD}"/tmp/overlay >/dev/null 2>&1
	mountpoint -q "${SDCARD}"/tmp/overlay || rm -r "${SDCARD}"/tmp/overlay
	if [[ $CUSTOMIZE_IMAGE_RC != 0 ]]; then
		exit_with_error "customize-image.sh exited with error (rc: $CUSTOMIZE_IMAGE_RC)"
	fi

	call_hook_point "post_customize_image" "image_tweaks_post_customize" << 'POST_CUSTOMIZE_IMAGE'
*post customize-image.sh hook*
Run after the customize-image.sh script is run, and the overlay is unmounted.
POST_CUSTOMIZE_IMAGE

} #############################################################################

install_deb_chroot()
{
	local package=$1
	local variant=$2
	local transfer=$3
	local name
	local desc
	if [[ ${variant} != remote ]]; then
		name="/root/"$(basename "${package}")
		[[ ! -f "${SDCARD}${name}" ]] && cp "${package}" "${SDCARD}${name}"
		desc=""
	else
		name=$1
		desc=" from repository"
	fi

	display_alert "Installing${desc}" "${name/\/root\//}"
	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	# when building in bulk from remote, lets make sure we have up2date index
	[[ $BUILD_ALL == yes && ${variant} == remote ]] && chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get $apt_extra -yqq update"
	chroot "${SDCARD}" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -yqq $apt_extra --no-install-recommends install $name" >> "${DEST}"/debug/install.log 2>&1
	[[ $? -ne 0 ]] && exit_with_error "Installation of $name failed" "${BOARD} ${RELEASE} ${BUILD_DESKTOP} ${LINUXFAMILY}"
	[[ ${variant} == remote && ${transfer} == yes ]] && rsync -rq "${SDCARD}"/var/cache/apt/archives/*.deb ${DEB_STORAGE}/
}
