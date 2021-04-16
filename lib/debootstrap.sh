# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# debootstrap_ng
# create_rootfs_cache
# prepare_partitions
# update_initramfs
# create_image

# debootstrap_ng
#
debootstrap_ng()
{
	display_alert "Starting rootfs and image building process for" "${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL}" "info"

	[[ $ROOTFS_TYPE != ext4 ]] && display_alert "Assuming $BOARD $BRANCH kernel supports $ROOTFS_TYPE" "" "wrn"

	# trap to unmount stuff in case of error/manual interruption
	trap unmount_on_exit INT TERM EXIT

	# stage: clean and create directories
	rm -rf $SDCARD $MOUNT
	mkdir -p $SDCARD $MOUNT $DEST/images $SRC/cache/rootfs

	# stage: verify tmpfs configuration and mount
	# default maximum size for tmpfs mount is 1/2 of available RAM
	# CLI needs ~1.2GiB+ (Xenial CLI), Desktop - ~2.8GiB+ (Xenial Desktop w/o HW acceleration)
	# calculate and set tmpfs mount to use 2/3 of available RAM
	local phymem=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 * 2 / 3 )) # MiB
	if [[ $BUILD_DESKTOP == yes ]]; then local tmpfs_max_size=3500; else local tmpfs_max_size=1500; fi # MiB
	if [[ $FORCE_USE_RAMDISK == no ]]; then	local use_tmpfs=no
	elif [[ $FORCE_USE_RAMDISK == yes || $phymem -gt $tmpfs_max_size ]]; then
		local use_tmpfs=yes
	fi
	[[ -n $FORCE_TMPFS_SIZE ]] && phymem=$FORCE_TMPFS_SIZE

	[[ $use_tmpfs == yes ]] && mount -t tmpfs -o size=${phymem}M tmpfs $SDCARD

	# stage: prepare basic rootfs: unpack cache or create from scratch
	create_rootfs_cache

	# stage: install kernel and u-boot packages
	# install distribution and board specific applications

	install_distribution_specific
	install_common

	# install locally built packages
	[[ $EXTERNAL_NEW == compile ]] && chroot_installpackages_local >> "${DEST}"/debug/install.log 2>&1

	# install from apt.armbian.com
	[[ $EXTERNAL_NEW == prebuilt ]] && chroot_installpackages "yes" >> "${DEST}"/debug/install.log 2>&1

	# stage: user customization script
	# NOTE: installing too many packages may fill tmpfs mount
	customize_image

	# create list of installed packages for debug purposes
	chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > $DEST/debug/installed-packages-${RELEASE}$([[ ${BUILD_MINIMAL} == yes ]] && echo "-minimal")$([[ ${BUILD_DESKTOP} == yes  ]] && echo "-desktop").list 2>&1

	# clean up / prepare for making the image
	umount_chroot "$SDCARD"
	post_debootstrap_tweaks

	if [[ $ROOTFS_TYPE == fel ]]; then
		FEL_ROOTFS=$SDCARD/
		display_alert "Starting FEL boot" "$BOARD" "info"
		source $SRC/lib/fel-load.sh
	else
		prepare_partitions
		create_image
	fi

	# stage: unmount tmpfs
	umount $SDCARD 2>&1
	if [[ $use_tmpfs = yes ]]; then
		while grep -qs "$SDCARD" /proc/mounts
		do
			umount $SDCARD
			sleep 5
		done
	fi
	rm -rf $SDCARD

	# remove exit trap
	trap - INT TERM EXIT
} #############################################################################

# create_rootfs_cache
#
# unpacks cached rootfs for $RELEASE or creates one
#
create_rootfs_cache()
{
	if [[ "$ROOT_FS_CREATE_ONLY" == "force" ]]; then
		local cycles=1
		else
		local cycles=2
	fi
	# seek last cache, proceed to previous otherwise build it
	for ((n=0;n<${cycles};n++)); do

		local packages_hash=$(get_package_list_hash "$(($ROOTFSCACHE_VERSION - $n))")
		[[ -z ${FORCED_MONTH_OFFSET} ]] && FORCED_MONTH_OFFSET=${n}
		local packages_hash=$(get_package_list_hash "$(date -d "$D +${FORCED_MONTH_OFFSET} month" +"%Y-%m-module$ROOTFSCACHE_VERSION" | sed 's/^0*//')")
		local cache_type="cli"
		[[ ${BUILD_DESKTOP} == yes ]] && local cache_type="xfce-desktop"
		[[ -n ${DESKTOP_ENVIRONMENT} ]] && local cache_type="${DESKTOP_ENVIRONMENT}"
		[[ ${BUILD_MINIMAL} == yes ]] && local cache_type="minimal"
		local cache_name=${RELEASE}-${cache_type}-${ARCH}.$packages_hash.tar.lz4
		local cache_fname=${SRC}/cache/rootfs/${cache_name}
		local display_name=${RELEASE}-${cache_type}-${ARCH}.${packages_hash:0:3}...${packages_hash:29}.tar.lz4

		display_alert "Checking for local cache" "$display_name" "info"

		if [[ ! -f $cache_fname && "$ROOT_FS_CREATE_ONLY" != "force" ]]; then
			display_alert "searching on servers"
			download_and_verify "_rootfs" "$cache_name"
		fi

		if [[ -f $cache_fname ]]; then
			break
		else
			display_alert "not found: try to use previous cache"
		fi

	done

	if [[ -f $cache_fname && "$ROOT_FS_CREATE_ONLY" != "force" ]]; then
		local date_diff=$(( ($(date +%s) - $(stat -c %Y $cache_fname)) / 86400 ))
		display_alert "Extracting $display_name" "$date_diff days old" "info"
		pv -p -b -r -c -N "[ .... ] $display_name" "$cache_fname" | lz4 -dc | tar xp --xattrs -C $SDCARD/
		[[ $? -ne 0 ]] && rm $cache_fname && exit_with_error "Cache $cache_fname is corrupted and was deleted. Restart."
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf
		create_sources_list "$RELEASE" "$SDCARD/"
	else
		display_alert "... remote not found" "Creating new rootfs cache for $RELEASE" "info"

		# stage: debootstrap base system
		if [[ $NO_APT_CACHER != yes ]]; then
			# apt-cacher-ng apt-get proxy parameter
			local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\""
			local apt_mirror="http://${APT_PROXY_ADDR:-localhost:3142}/$APT_MIRROR"
		else
			local apt_mirror="http://$APT_MIRROR"
		fi

		# fancy progress bars
		[[ -z $OUTPUT_DIALOG ]] && local apt_extra_progress="--show-progress -o DPKG::Progress-Fancy=1"


		display_alert "Installing base system" "Stage 1/2" "info"
		eval 'debootstrap --variant=minbase --include=${DEBOOTSTRAP_LIST// /,} ${PACKAGE_LIST_EXCLUDE:+ --exclude=${PACKAGE_LIST_EXCLUDE// /,}} \
			--arch=$ARCH --components=${DEBOOTSTRAP_COMPONENTS} --foreign $RELEASE $SDCARD/ $apt_mirror' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 1/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/debootstrap/debootstrap ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} first stage failed"

		cp /usr/bin/$QEMU_BINARY $SDCARD/usr/bin/

		mkdir -p $SDCARD/usr/share/keyrings/
		cp /usr/share/keyrings/*-archive-keyring.gpg $SDCARD/usr/share/keyrings/

		display_alert "Installing base system" "Stage 2/2" "info"
		eval 'chroot $SDCARD /bin/bash -c "/debootstrap/debootstrap --second-stage"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Debootstrap (stage 2/2)..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 || ! -f $SDCARD/bin/bash ]] && exit_with_error "Debootstrap base system for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} second stage failed"

		mount_chroot "$SDCARD"

		# policy-rc.d script prevents starting or reloading services during image creation
		printf '#!/bin/sh\nexit 101' > $SDCARD/usr/sbin/policy-rc.d
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/initctl"
		chroot $SDCARD /bin/bash -c "dpkg-divert --quiet --local --rename --add /sbin/start-stop-daemon"
		printf '#!/bin/sh\necho "Warning: Fake start-stop-daemon called, doing nothing"' > $SDCARD/sbin/start-stop-daemon
		printf '#!/bin/sh\necho "Warning: Fake initctl called, doing nothing"' > $SDCARD/sbin/initctl
		chmod 755 $SDCARD/usr/sbin/policy-rc.d
		chmod 755 $SDCARD/sbin/initctl
		chmod 755 $SDCARD/sbin/start-stop-daemon

		# stage: configure language and locales
		display_alert "Configuring locales" "$DEST_LANG" "info"

		[[ -f $SDCARD/etc/locale.gen ]] && sed -i "s/^# $DEST_LANG/$DEST_LANG/" $SDCARD/etc/locale.gen
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "locale-gen $DEST_LANG"' ${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "update-locale LANG=$DEST_LANG LANGUAGE=$DEST_LANG LC_MESSAGES=$DEST_LANG"' \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		if [[ -f $SDCARD/etc/default/console-setup ]]; then
			sed -e 's/CHARMAP=.*/CHARMAP="UTF-8"/' -e 's/FONTSIZE=.*/FONTSIZE="8x16"/' \
				-e 's/CODESET=.*/CODESET="guess"/' -i $SDCARD/etc/default/console-setup
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "setupcon --save --force"'
		fi

		# stage: create apt-get sources list
		create_sources_list "$RELEASE" "$SDCARD/"

		# add armhf arhitecture to arm64
		[[ $ARCH == arm64 ]] && eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "dpkg --add-architecture armhf"'

		# this should fix resolvconf installation failure in some cases
		chroot $SDCARD /bin/bash -c 'echo "resolvconf resolvconf/linkify-resolvconf boolean false" | debconf-set-selections'

		# stage: update packages list
		display_alert "Updating package list" "$RELEASE" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "apt-get -q -y $apt_extra update"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Updating package lists..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && display_alert "Updating package lists" "failed" "wrn"

		# stage: upgrade base packages from xxx-updates and xxx-backports repository branches
		display_alert "Upgrading base packages" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress upgrade"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Upgrading base packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		# Myy: Dividing the desktop packages installation steps into multiple
		# ones. We first install the "ADDITIONAL_PACKAGES" in order to get
		# access to software-common-properties installation.
		# THEN we add the APT sources and install the Desktop packages.
		# TODO : Find a way to add APT sources WITHOUT software-common-properties

		[[ ${PIPESTATUS[0]} -ne 0 ]] && display_alert "Upgrading base packages" "failed" "wrn"

		# stage: install additional packages
		display_alert "Installing the main packages for" "Armbian" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress --no-install-recommends install $PACKAGE_MAIN_LIST"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian main packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian main packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"

		if [[ $BUILD_DESKTOP == "yes" ]]; then
			# FIXME Myy : Are we keeping this only for Desktop users,
			# or should we extend this to CLI users too ?
			# There might be some clunky boards that require Debian packages from
			# specific repos...
			display_alert "Adding apt sources for Desktop packages"
			add_desktop_package_sources

			local apt_desktop_install_flags=""
			if [[ ! -z ${DESKTOP_APT_FLAGS_SELECTED+x} ]]; then
				for flag in ${DESKTOP_APT_FLAGS_SELECTED}; do
					apt_desktop_install_flags+=" --install-${flag}"
				done
			else
				# Myy : Using the previous default option, if the variable isn't defined
				# And ONLY if it's not defined !
				apt_desktop_install_flags+=" --no-install-recommends"
			fi

			display_alert "Installing the desktop packages for" "Armbian" "info"
			eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
				$apt_extra $apt_extra_progress install ${apt_desktop_install_flags} $PACKAGE_LIST_DESKTOP"' \
				${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
				${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Installing Armbian desktop packages..." $TTY_Y $TTY_X'} \
				${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

			[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian desktop packages for ${BRANCH} ${BOARD} ${RELEASE} ${DESKTOP_APPGROUPS_SELECTED} ${DESKTOP_ENVIRONMENT} ${BUILD_MINIMAL} failed"
			
		fi

		# Remove packages from packages.uninstall

		display_alert "Uninstall packages" "$PACKAGE_LIST_UNINSTALL" "info"
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq \
			$apt_extra $apt_extra_progress purge $PACKAGE_LIST_UNINSTALL"' \
			${PROGRESS_LOG_TO_FILE:+' >> $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Removing packages.uninstall packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Installation of Armbian packages failed"

		# stage: purge residual packages
		display_alert "Purging residual packages for" "Armbian" "info"
		PURGINGPACKAGES=$(chroot $SDCARD /bin/bash -c "dpkg -l | grep \"^rc\" | awk '{print \$2}' | tr \"\n\" \" \"")
		eval 'LC_ALL=C LANG=C chroot $SDCARD /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get -y -q \
			$apt_extra $apt_extra_progress remove --purge $PURGINGPACKAGES"' \
			${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/debootstrap.log'} \
			${OUTPUT_DIALOG:+' | dialog --backtitle "$backtitle" --progressbox "Purging residual Armbian packages..." $TTY_Y $TTY_X'} \
			${OUTPUT_VERYSILENT:+' >/dev/null 2>/dev/null'}

		[[ ${PIPESTATUS[0]} -ne 0 ]] && exit_with_error "Purging of residual Armbian packages failed"

		# stage: remove downloaded packages
		chroot $SDCARD /bin/bash -c "apt-get clean"

		# DEBUG: print free space
		local freespace=$(LC_ALL=C df -h)
		echo $freespace >> $DEST/debug/debootstrap.log
		display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
		display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

		# create list of installed packages for debug purposes
		chroot $SDCARD /bin/bash -c "dpkg --get-selections" | grep -v deinstall | awk '{print $1}' | cut -f1 -d':' > ${cache_fname}.list 2>&1

		# creating xapian index that synaptic runs faster
		if [[ $BUILD_DESKTOP == yes ]]; then
			display_alert "Recreating Synaptic search index" "Please wait" "info"
			chroot $SDCARD /bin/bash -c "[[ -f /usr/sbin/update-apt-xapian-index ]] && /usr/sbin/update-apt-xapian-index -u"
		fi

		# this is needed for the build process later since resolvconf generated file in /run is not saved
		rm $SDCARD/etc/resolv.conf
		echo "nameserver $NAMESERVER" >> $SDCARD/etc/resolv.conf

		# stage: make rootfs cache archive
		display_alert "Ending debootstrap process and preparing cache" "$RELEASE" "info"
		sync
		# the only reason to unmount here is compression progress display
		# based on rootfs size calculation
		umount_chroot "$SDCARD"

		tar cp --xattrs --directory=$SDCARD/ --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "$display_name" | lz4 -5 -c > $cache_fname

		# sign rootfs cache archive that it can be used for web cache once. Internal purposes
		if [[ -n $GPG_PASS ]]; then
			echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes $cache_fname
		fi

	fi

	# used for internal purposes. Faster rootfs cache rebuilding
	if [[ -n "$ROOT_FS_CREATE_ONLY" ]]; then
		[[ $use_tmpfs = yes ]] && umount $SDCARD
		rm -rf $SDCARD
		# remove exit trap
		trap - INT TERM EXIT
        exit
	fi

	mount_chroot "$SDCARD"
} #############################################################################

# prepare_partitions
#
# creates image file, partitions and fs
# and mounts it to local dir
# FS-dependent stuff (boot and root fs partition types) happens here
#
prepare_partitions()
{
	display_alert "Preparing image file for rootfs" "$BOARD $RELEASE" "info"

	# possible partition combinations
	# /boot: none, ext4, ext2, fat (BOOTFS_TYPE)
	# root: ext4, btrfs, f2fs, nfs (ROOTFS_TYPE)

	# declare makes local variables by default if used inside a function
	# NOTE: mountopts string should always start with comma if not empty

	# array copying in old bash versions is tricky, so having filesystems as arrays
	# with attributes as keys is not a good idea
	declare -A parttype mkopts mkfs mountopts

	parttype[ext4]=ext4
	parttype[ext2]=ext2
	parttype[fat]=fat16
	parttype[f2fs]=ext4 # not a copy-paste error
	parttype[btrfs]=btrfs
	parttype[xfs]=xfs
	# parttype[nfs] is empty

	# metadata_csum and 64bit may need to be disabled explicitly when migrating to newer supported host OS releases
	if [[ $(lsb_release -sc) =~ bionic|buster|bullseye|cosmic|groovy|focal|hirsute|sid ]]; then
		mkopts[ext4]='-q -m 2 -O ^64bit,^metadata_csum'
	elif [[ $(lsb_release -sc) == xenial ]]; then
		mkopts[ext4]='-q -m 2'
	fi
	mkopts[fat]='-n BOOT'
	mkopts[ext2]='-q'
	# mkopts[f2fs] is empty
	mkopts[btrfs]='-m dup'
	# mkopts[xfs] is empty
	# mkopts[nfs] is empty

	mkfs[ext4]=ext4
	mkfs[ext2]=ext2
	mkfs[fat]=vfat
	mkfs[f2fs]=f2fs
	mkfs[btrfs]=btrfs
	mkfs[xfs]=xfs
	# mkfs[nfs] is empty

	mountopts[ext4]=',commit=600,errors=remount-ro'
	# mountopts[ext2] is empty
	# mountopts[fat] is empty
	# mountopts[f2fs] is empty
	mountopts[btrfs]=',commit=600'
	# mountopts[xfs] is empty
	# mountopts[nfs] is empty

	# default BOOTSIZE to use if not specified
	DEFAULT_BOOTSIZE=256	# MiB

	# stage: determine partition configuration
	if [[ -n $BOOTFS_TYPE ]]; then
		# 2 partition setup with forced /boot type
		local bootfs=$BOOTFS_TYPE
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE != ext4 && $ROOTFS_TYPE != nfs ]]; then
		# 2 partition setup for non-ext4 local root
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	elif [[ $ROOTFS_TYPE == nfs ]]; then
		# single partition ext4 /boot, no root
		local bootfs=ext4
		local bootpart=1
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE} # For cleanup processing only
	elif [[ $CRYPTROOT_ENABLE == yes ]]; then
		# 2 partition setup for encrypted /root and non-encrypted /boot
		local bootfs=ext4
		local bootpart=1
		local rootpart=2
		[[ -z $BOOTSIZE || $BOOTSIZE -le 8 ]] && BOOTSIZE=${DEFAULT_BOOTSIZE}
	else
		# single partition ext4 root
		local rootpart=1
		BOOTSIZE=0
	fi

	# stage: calculate rootfs size
	local rootfs_size=$(du -sm $SDCARD/ | cut -f1) # MiB
	display_alert "Current rootfs size" "$rootfs_size MiB" "info"
	if [[ -n $FIXED_IMAGE_SIZE && $FIXED_IMAGE_SIZE =~ ^[0-9]+$ ]]; then
		display_alert "Using user-defined image size" "$FIXED_IMAGE_SIZE MiB" "info"
		local sdsize=$FIXED_IMAGE_SIZE
		# basic sanity check
		if [[ $ROOTFS_TYPE != nfs && $sdsize -lt $rootfs_size ]]; then
			exit_with_error "User defined image size is too small" "$sdsize <= $rootfs_size"
		fi
	else
		local imagesize=$(( $rootfs_size + $OFFSET + $BOOTSIZE )) # MiB
		case $ROOTFS_TYPE in
			btrfs)
				# Used for server images, currently no swap functionality, so disk space
				if [[ $BTRFS_COMPRESSION == none ]]; then
					local sdsize=$(bc -l <<< "scale=0; (($imagesize * 1.25) / 4 + 1) * 4")
				else
					# requirements are rather low since rootfs gets filled with compress-force=zlib
					local sdsize=$(bc -l <<< "scale=0; (($imagesize * 0.8) / 4 + 1) * 4")
				fi
				;;
			*)
				# Hardcoded overhead +25% is needed for desktop images,
				# for CLI it could be lower. Align the size up to 4MiB
				if [[ $BUILD_DESKTOP == yes ]]; then
					local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.30) / 1 + 0) / 4 + 1) * 4")
				else
					local sdsize=$(bc -l <<< "scale=0; ((($imagesize * 1.25) / 1 + 0) / 4 + 1) * 4")
				fi
				;;
		esac
	fi

	# stage: create blank image
	display_alert "Creating blank image for rootfs" "$sdsize MiB" "info"
	if [[ $FAST_CREATE_IMAGE == yes ]]; then
		truncate --size=${sdsize}M ${SDCARD}.raw # sometimes results in fs corruption, revert to previous know to work solution
		sync
	else
		dd if=/dev/zero bs=1M status=none count=$sdsize | pv -p -b -r -s $(( $sdsize * 1024 * 1024 )) -N "[ .... ] dd" | dd status=none of=${SDCARD}.raw
	fi

	# stage: calculate boot partition size
	local bootstart=$(($OFFSET * 2048))
	local rootstart=$(($bootstart + ($BOOTSIZE * 2048)))
	local bootend=$(($rootstart - 1))

	# stage: create partition table
	display_alert "Creating partitions" "${bootfs:+/boot: $bootfs }root: $ROOTFS_TYPE" "info"
	parted -s ${SDCARD}.raw -- mklabel ${IMAGE_PARTITION_TABLE}
	if [[ $ROOTFS_TYPE == nfs ]]; then
		# single /boot partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s 100%
	elif [[ $BOOTSIZE == 0 ]]; then
		# single root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s 100%
	else
		# /boot partition + root partition
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$bootfs]} ${bootstart}s ${bootend}s
		parted -s ${SDCARD}.raw -- mkpart primary ${parttype[$ROOTFS_TYPE]} ${rootstart}s 100%
	fi

	# stage: mount image
	# lock access to loop devices
	exec {FD}>/var/lock/armbian-debootstrap-losetup
	flock -x $FD

	LOOP=$(losetup -f)
	[[ -z $LOOP ]] && exit_with_error "Unable to find free loop device"

	check_loop_device "$LOOP"

	losetup $LOOP ${SDCARD}.raw

	# loop device was grabbed here, unlock
	flock -u $FD

	partprobe $LOOP

	# stage: create fs, mount partitions, create fstab
	rm -f $SDCARD/etc/fstab
	if [[ -n $rootpart ]]; then
		local rootdevice="${LOOP}p${rootpart}"

		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			display_alert "Encrypting root partition with LUKS..." "cryptsetup luksFormat $rootdevice" ""
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksFormat $CRYPTROOT_PARAMETERS $rootdevice -
			echo -n $CRYPTROOT_PASSPHRASE | cryptsetup luksOpen $rootdevice $ROOT_MAPPER -
			display_alert "Root partition encryption complete." "" "ext"
			# TODO: pass /dev/mapper to Docker
			rootdevice=/dev/mapper/$ROOT_MAPPER # used by `mkfs` and `mount` commands
		fi

		check_loop_device "$rootdevice"
		display_alert "Creating rootfs" "$ROOTFS_TYPE on $rootdevice"
		mkfs.${mkfs[$ROOTFS_TYPE]} ${mkopts[$ROOTFS_TYPE]} $rootdevice >> "${DEST}"/debug/install.log 2>&1
		[[ $ROOTFS_TYPE == ext4 ]] && tune2fs -o journal_data_writeback $rootdevice > /dev/null
		if [[ $ROOTFS_TYPE == btrfs && $BTRFS_COMPRESSION != none ]]; then
			local fscreateopt="-o compress-force=${BTRFS_COMPRESSION}"
		fi
		mount ${fscreateopt} $rootdevice $MOUNT/
		# create fstab (and crypttab) entry
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			# map the LUKS container partition via its UUID to be the 'cryptroot' device
			echo "$ROOT_MAPPER UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}) none luks" >> $SDCARD/etc/crypttab
			local rootfs=$rootdevice # used in fstab
		else
			local rootfs="UUID=$(blkid -s UUID -o value $rootdevice)"
		fi
		echo "$rootfs / ${mkfs[$ROOTFS_TYPE]} defaults,noatime${mountopts[$ROOTFS_TYPE]} 0 1" >> $SDCARD/etc/fstab
	fi
	if [[ -n $bootpart ]]; then
		display_alert "Creating /boot" "$bootfs on ${LOOP}p${bootpart}"
		check_loop_device "${LOOP}p${bootpart}"
		mkfs.${mkfs[$bootfs]} ${mkopts[$bootfs]} ${LOOP}p${bootpart} >> "${DEST}"/debug/install.log 2>&1
		mkdir -p $MOUNT/boot/
		mount ${LOOP}p${bootpart} $MOUNT/boot/
		echo "UUID=$(blkid -s UUID -o value ${LOOP}p${bootpart}) /boot ${mkfs[$bootfs]} defaults${mountopts[$bootfs]} 0 2" >> $SDCARD/etc/fstab
	fi
	[[ $ROOTFS_TYPE == nfs ]] && echo "/dev/nfs / nfs defaults 0 0" >> $SDCARD/etc/fstab
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> $SDCARD/etc/fstab

	# stage: adjust boot script or boot environment
	if [[ -f $SDCARD/boot/armbianEnv.txt ]]; then
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			echo "rootdev=$rootdevice cryptdevice=UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart}):$ROOT_MAPPER" >> $SDCARD/boot/armbianEnv.txt
		else
			echo "rootdev=$rootfs" >> $SDCARD/boot/armbianEnv.txt
		fi
		echo "rootfstype=$ROOTFS_TYPE" >> $SDCARD/boot/armbianEnv.txt
	elif [[ $rootpart != 1 ]]; then
		local bootscript_dst=${BOOTSCRIPT##*:}
		sed -i 's/mmcblk0p1/mmcblk0p2/' $SDCARD/boot/$bootscript_dst
		sed -i -e "s/rootfstype=ext4/rootfstype=$ROOTFS_TYPE/" \
			-e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/$bootscript_dst
	fi

	# if we have boot.ini = remove armbianEnv.txt and add UUID there if enabled
	if [[ -f $SDCARD/boot/boot.ini ]]; then
		sed -i -e "s/rootfstype \"ext4\"/rootfstype \"$ROOTFS_TYPE\"/" $SDCARD/boot/boot.ini
		if [[ $CRYPTROOT_ENABLE == yes ]]; then
			local rootpart="UUID=$(blkid -s UUID -o value ${LOOP}p${rootpart})"
			sed -i 's/^setenv rootdev .*/setenv rootdev "\/dev\/mapper\/'$ROOT_MAPPER' cryptdevice='$rootpart':'$ROOT_MAPPER'"/' $SDCARD/boot/boot.ini
		else
			sed -i 's/^setenv rootdev .*/setenv rootdev "'$rootfs'"/' $SDCARD/boot/boot.ini
		fi
		if [[  $LINUXFAMILY != meson64 ]]; then
			[[ -f $SDCARD/boot/armbianEnv.txt ]] && rm $SDCARD/boot/armbianEnv.txt
		fi
	fi

	# if we have a headless device, set console to DEFAULT_CONSOLE
	if [[ -n $DEFAULT_CONSOLE && -f $SDCARD/boot/armbianEnv.txt ]]; then
		if grep -lq "^console=" $SDCARD/boot/armbianEnv.txt; then
			sed -i "s/console=.*/console=$DEFAULT_CONSOLE/" $SDCARD/boot/armbianEnv.txt
		else
			echo "console=$DEFAULT_CONSOLE" >> $SDCARD/boot/armbianEnv.txt
        fi
	fi

	# recompile .cmd to .scr if boot.cmd exists
	[[ -f $SDCARD/boot/boot.cmd ]] && \
		mkimage -C none -A arm -T script -d $SDCARD/boot/boot.cmd $SDCARD/boot/boot.scr > /dev/null 2>&1

} #############################################################################

# update_initramfs
#
# this should be invoked as late as possible for any modifications by
# customize_image (userpatches) and prepare_partitions to be reflected in the
# final initramfs
#
# especially, this needs to be invoked after /etc/crypttab has been created
# for cryptroot-unlock to work:
# https://serverfault.com/questions/907254/cryproot-unlock-with-dropbear-timeout-while-waiting-for-askpass
#
# since Debian buster, it has to be called within create_image() on the $MOUNT
# path instead of $SDCARD (which can be a tmpfs and breaks cryptsetup-initramfs).
# see: https://github.com/armbian/build/issues/1584
#
update_initramfs()
{
	local chroot_target=$1
	update_initramfs_cmd="update-initramfs -uv -k ${VER}-${LINUXFAMILY}"
	display_alert "Updating initramfs..." "$update_initramfs_cmd" ""
	cp /usr/bin/$QEMU_BINARY $chroot_target/usr/bin/
	mount_chroot "$chroot_target/"

	chroot $chroot_target /bin/bash -c "$update_initramfs_cmd" >> $DEST/debug/install.log 2>&1
	display_alert "Updated initramfs." "for details see: $DEST/debug/install.log" "info"

	display_alert "Re-enabling" "initramfs-tools hook for kernel"
	chroot $chroot_target /bin/bash -c "chmod -v +x /etc/kernel/postinst.d/initramfs-tools" >> "${DEST}"/debug/install.log 2>&1

	umount_chroot "$chroot_target/"
	rm $chroot_target/usr/bin/$QEMU_BINARY

} #############################################################################

# create_image
#
# finishes creation of image from cached rootfs
#
create_image()
{
	# stage: create file name
	local version="Armbian_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $ROOTFS_TYPE == nfs ]] && version=${version}_nfsboot

	if [[ $ROOTFS_TYPE != nfs ]]; then
		display_alert "Copying files to" "/"
		rsync -aHWXh --exclude="/boot/*" --exclude="/dev/*" --exclude="/proc/*" --exclude="/run/*" --exclude="/tmp/*" \
			--exclude="/sys/*" --info=progress2,stats1 $SDCARD/ $MOUNT/ >> "${DEST}"/debug/install.log 2>&1
	else
		display_alert "Creating rootfs archive" "rootfs.tgz" "info"
		tar cp --xattrs --directory=$SDCARD/ --exclude='./boot/*' --exclude='./dev/*' --exclude='./proc/*' --exclude='./run/*' --exclude='./tmp/*' \
			--exclude='./sys/*' . | pv -p -b -r -s $(du -sb $SDCARD/ | cut -f1) -N "rootfs.tgz" | gzip -c > $DEST/images/${version}-rootfs.tgz
	fi

	# stage: rsync /boot
	display_alert "Copying files to" "/boot"
	if [[ $(findmnt --target $MOUNT/boot -o FSTYPE -n) == vfat ]]; then
		# fat32
		rsync -rLtWh --info=progress2,stats1 $SDCARD/boot $MOUNT >> "${DEST}"/debug/install.log 2>&1
	else
		# ext4
		rsync -aHWXh --info=progress2,stats1 $SDCARD/boot $MOUNT >> "${DEST}"/debug/install.log 2>&1
	fi

	# stage: create final initramfs
	update_initramfs $MOUNT

	# DEBUG: print free space
	local freespace=$(LC_ALL=C df -h)
	echo $freespace >> $DEST/debug/debootstrap.log
	display_alert "Free SD cache" "$(echo -e "$freespace" | grep $SDCARD | awk '{print $5}')" "info"
	display_alert "Mount point" "$(echo -e "$freespace" | grep $MOUNT | head -1 | awk '{print $5}')" "info"

	# stage: write u-boot
	write_uboot $LOOP

	# fix wrong / permissions
	chmod 755 $MOUNT

	# unmount /boot first, rootfs second, image file last
	sync
	[[ $BOOTSIZE != 0 ]] && umount -l $MOUNT/boot
	[[ $ROOTFS_TYPE != nfs ]] && umount -l $MOUNT
	[[ $CRYPTROOT_ENABLE == yes ]] && cryptsetup luksClose $ROOT_MAPPER

	# to make sure its unmounted
	while grep -Eq '(${MOUNT}|${DESTIMG})' /proc/mounts
	do
		display_alert "Unmounting" "${MOUNT}" "info"
		sleep 5
	done

	losetup -d $LOOP
	rm -rf --one-file-system $DESTIMG $MOUNT

	mkdir -p $DESTIMG
	mv ${SDCARD}.raw $DESTIMG/${version}.img

	FINALDEST=$DEST/images

	if [[ $BUILD_ALL == yes ]]; then
		if [[ "$BETA" == yes ]]; then
			FINALDEST=$DEST/images/"${BOARD}"/nightly
			else
			FINALDEST=$DEST/images/"${BOARD}"/archive
		fi
		install -d -o nobody -g nogroup -m 775 ${FINALDEST}
	fi


	if [[ -z $SEND_TO_SERVER ]]; then

		if [[ $COMPRESS_OUTPUTIMAGE == "" || $COMPRESS_OUTPUTIMAGE == no ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,img"
		elif [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
			COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
			display_alert "Compressing" "${FINALDEST}/${version}.img.gz" "info"
			pigz -3 < $DESTIMG/${version}.img > ${FINALDEST}/${version}.img.gz
			compression_type=".gz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
			display_alert "Compressing" "${FINALDEST}/${version}.img.xz" "info"
			# compressing consumes a lot of memory we don't have. Waiting for previous packing job to finish helps to run a lot more builds in parallel
			[[ ${BUILD_ALL} == yes && $(free | grep Mem | awk '{print $4/$2 * 100}' | awk '{print int($1+0.5)}') -lt 50 ]] && while [[ $(ps -uax | grep "pixz" | wc -l) -gt 5 ]]; do echo -en "#"; sleep 2; done
			pixz -9 < $DESTIMG/${version}.img > ${FINALDEST}/${version}.img.xz
			compression_type=".xz"
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *img* || $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			mv $DESTIMG/${version}.img ${FINALDEST}/${version}.img || exit 1
			compression_type=""
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
			cd ${FINALDEST}
			display_alert "SHA256 calculating" "${version}.img${compression_type}" "info"
			sha256sum -b ${version}.img${compression_type} > ${version}.img${compression_type}.sha
		fi

		if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
			cd ${FINALDEST}
			if [[ -n $GPG_PASS ]]; then
				display_alert "GPG signing" "${version}.img${compression_type}" "info"
				echo $GPG_PASS | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes ${FINALDEST}/${version}.img${compression_type} || exit 1
			else
				display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
			fi
		fi

		fingerprint_image "${FINALDEST}/${version}.img${compression_type}.txt" "${version}"

		if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
			display_alert "Compressing" "${FINALDEST}/${version}.7z" "info"
			7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on \
			${FINALDEST}/${version}.7z ${version}.key ${version}.img* >/dev/null 2>&1
			find ${FINALDEST}/ -type \
			f \( -name "${version}.img" -o -name "${version}.img.asc" -o -name "${version}.img.txt" -o -name "${version}.img.sha" \) -print0 \
			| xargs -0 rm >/dev/null 2>&1
		fi

		rm -rf $DESTIMG
	fi
	display_alert "Done building" "${FINALDEST}/${version}.img" "info"

	# call custom post build hook
	[[ $(type -t post_build_image) == function ]] && post_build_image "${FINALDEST}/${version}.img"

	# write image to SD card
	if [[ $(lsblk "$CARD_DEVICE" 2>/dev/null) && -f ${FINALDEST}/${version}.img ]]; then

		# make sha256sum if it does not exists. we need it for comparisson
		if [[ -f "${FINALDEST}/${version}".img.sha ]]; then
			local ifsha=$(cat ${FINALDEST}/${version}.img.sha | awk '{print $1}')
		else
			local ifsha=$(sha256sum -b "${FINALDEST}/${version}".img | awk '{print $1}')
		fi

		display_alert "Writing image" "$CARD_DEVICE ${readsha}" "info"

		# write to SD card
		pv -p -b -r -c -N "[ .... ] dd" ${FINALDEST}/${version}.img | dd of=$CARD_DEVICE bs=1M iflag=fullblock oflag=direct status=none

		# read and compare
		display_alert "Verifying. Please wait!"
		local ofsha=$(dd if=$CARD_DEVICE count=$(du -b ${FINALDEST}/${version}.img | cut -f1) status=none iflag=count_bytes oflag=direct | sha256sum | awk '{print $1}')
		if [[ $ifsha == $ofsha ]]; then
			display_alert "Writing verified" "${version}.img" "info"
		else
			display_alert "Writing failed" "${version}.img" "err"
		fi
	elif [[ `systemd-detect-virt` == 'docker' && -n $CARD_DEVICE ]]; then
		# display warning when we want to write sd card under Docker
		display_alert "Can't write to $CARD_DEVICE" "Enable docker privileged mode in config-docker.conf" "wrn"
	fi

} #############################################################################
