
#
# Copyright (c) 2015 Igor Pecovnik, igor.pecovnik@gma**.com
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# compilation_prepare

compilation_prepare()
{

	# Packaging patch for modern kernels should be one for all. 
	# Currently we have it per kernel family since we can't have one
	# Maintaining one from central location starting with 5.3+
	# Temporally set for new "default->legacy,next->current" family naming

	if linux-version compare "${version}" ge 5.10; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.10.y.patch" "applying"
	elif linux-version compare "${version}" ge 5.8.17 \
		&& linux-version compare "${version}" le 5.9 \
		|| linux-version compare "${version}" ge 5.9.2; then
			display_alert "Adjusting" "packaging" "info"
			cd "$kerneldir" || exit
			process_patch_file "${SRC}/patch/misc/general-packaging-5.8-9.y.patch" "applying"
	elif linux-version compare "${version}" ge 5.6; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.6.y.patch" "applying"
	elif linux-version compare "${version}" ge 5.3; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-5.3.y.patch" "applying"
	fi

	if [[ "${version}" == "4.19."* ]] && [[ "$LINUXFAMILY" == sunxi* || "$LINUXFAMILY" == meson64 || \
	"$LINUXFAMILY" == mvebu64 || "$LINUXFAMILY" == mt7623 || "$LINUXFAMILY" == mvebu ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.19.y.patch" "applying"
	fi

	if [[ "${version}" == "4.14."* ]] && [[ "$LINUXFAMILY" == s5p6818 || "$LINUXFAMILY" == mvebu64 || \
	"$LINUXFAMILY" == imx7d || "$LINUXFAMILY" == odroidxu4 || "$LINUXFAMILY" == mvebu ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.14.y.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* || "${version}" == "4.9."* ]] && \
	[[ "$LINUXFAMILY" == rockpis || "$LINUXFAMILY" == rk3399 ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y-rk3399.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* ]] && \
	[[ "$LINUXFAMILY" == rockchip64 || "$LINUXFAMILY" == station* ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y-rockchip64.patch" "applying"
	fi

	if [[ "${version}" == "4.4."* ]] && [[ "$LINUXFAMILY" == rockchip || "$LINUXFAMILY" == rk322x ]]; then
                display_alert "Adjusting" "packaging" "info"
                cd "$kerneldir" || exit
                process_patch_file "${SRC}/patch/misc/general-packaging-4.4.y.patch" "applying"
        fi

	if [[ "${version}" == "4.9."* ]] && [[ "$LINUXFAMILY" == meson64 || "$LINUXFAMILY" == odroidc4 ]]; then
		display_alert "Adjusting" "packaging" "info"
		cd "$kerneldir" || exit
		process_patch_file "${SRC}/patch/misc/general-packaging-4.9.y.patch" "applying"
	fi

	#
	# Linux splash file
	#

	if linux-version compare "${version}" ge 5.8.10; then

		display_alert "Adding" "Kernel splash file" "info"

		process_patch_file "${SRC}/patch/misc/bootsplash-5.8.10-0001-Revert-vgacon-remove-software-scrollback-support.patch" "applying"
		process_patch_file "${SRC}/patch/misc/bootsplash-5.8.10-0002-Revert-fbcon-remove-now-unusued-softback_lines-curso.patch" "applying"
		if linux-version compare "${version}" ge 5.10; then
			process_patch_file "${SRC}/patch/misc/bootsplash-5.10.y-0003-Revert-fbcon-remove-soft-scrollback-code.patch" "applying"
		else
			process_patch_file "${SRC}/patch/misc/bootsplash-5.8.10-0003-Revert-fbcon-remove-soft-scrollback-code.patch" "applying"
		fi

		process_patch_file "${SRC}/patch/misc/0001-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0002-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0003-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0004-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0005-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0006-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0007-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0008-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0009-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0010-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0011-bootsplash.patch" "applying"
		process_patch_file "${SRC}/patch/misc/0012-bootsplash.patch" "applying"

	fi

	#
	# mac80211 wireless driver injection features from Kali Linux
	#

	if linux-version compare "${version}" ge 5.4 && [ $EXTRAWIFI == yes ]; then

		display_alert "Adding" "Wireless package injections for mac80211 compatible chipsets" "info"
		if linux-version compare "${version}" ge 5.9; then
			process_patch_file "${SRC}/patch/misc/kali-wifi-injection-1-v5.9-post.patch" "applying"
		else
			process_patch_file "${SRC}/patch/misc/kali-wifi-injection-1-pre-v5.9.patch" "applying"
		fi
		process_patch_file "${SRC}/patch/misc/kali-wifi-injection-2.patch" "applying"
		process_patch_file "${SRC}/patch/misc/kali-wifi-injection-3.patch" "applying"

	fi

	# AUFS - advanced multi layered unification filesystem for Kernel > 5.1
	#
	# Older versions have AUFS support with a patch

	if linux-version compare "${version}" ge 5.1 && linux-version compare "${version}" le 5.12 && [ "$AUFS" == yes ]; then

		# attach to specifics tag or branch
		local aufstag
		aufstag=$(echo "${version}" | cut -f 1-2 -d ".")

		# manual overrides
		if linux-version compare "${version}" ge 5.4.3 && linux-version compare "${version}" le 5.5 ; then aufstag="5.4.3"; fi

		# check if Mr. Okajima already made a branch for this version
		improved_git ls-remote --exit-code --heads https://github.com/sfjro/aufs5-standalone "aufs${aufstag}" >/dev/null

		if [ "$?" -ne "0" ]; then
			# then use rc branch
			aufstag="5.x-rcN"
			improved_git ls-remote --exit-code --heads https://github.com/sfjro/aufs5-standalone "aufs${aufstag}" >/dev/null
		fi

		if [ "$?" -eq "0" ]; then

			display_alert "Adding" "AUFS ${aufstag}" "info"
			local aufsver="branch:aufs${aufstag}"
			fetch_from_repo "https://github.com/sfjro/aufs5-standalone" "aufs5" "branch:${aufsver}" "yes"
			cd "$kerneldir" || exit
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-kbuild.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-base.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-mmap.patch" "applying"
			process_patch_file "${SRC}/cache/sources/aufs5/${aufsver#*:}/aufs5-standalone.patch" "applying"
			cp -R "${SRC}/cache/sources/aufs5/${aufsver#*:}"/{Documentation,fs} .
			cp "${SRC}/cache/sources/aufs5/${aufsver#*:}"/include/uapi/linux/aufs_type.h include/uapi/linux/

		fi
	fi


	# ZFS
	if linux-version compare "${version}" ge 3.10; then

		# attach to specifics tag or branch


		# prepare kernel
		cd "$kerneldir" || exit
		local toolchain
		toolchain=$(find_toolchain "$KERNEL_COMPILER" "$KERNEL_USE_GCC")
		make ARCH=$ARCHITECTURE CROSS_COMPILE="$CCACHE $KERNEL_COMPILER" mrproper
		cp "${DEST}/config/${LINUXCONFIG}.config" .config
		yes "" | make ARCH=$ARCHITECTURE CROSS_COMPILE="$KERNEL_COMPILER" oldconfig
		make ARCH=$ARCHITECTURE CROSS_COMPILE="$KERNEL_COMPILER" prepare
		make ARCH=$ARCHITECTURE CROSS_COMPILE="$KERNEL_COMPILER" scripts
		local zfsver="tag:zfs-0.8.5"
		display_alert "Adding" "ZFS for Linux ${wirever} " "info"
		fetch_from_repo "https://github.com/zfsonlinux/zfs.git" "zfs" "${zfsver}" "yes"
		cd "${SRC}/cache/sources/zfs/${zfsver#*:}"
		sh autogen.sh
		./configure --prefix=/ --libdir=/lib --includedir=/usr/include --with-config=kernel --datarootdir=/usr/share --enable-linux-builtin=yes --with-linux="${kerneldir}" --with-linux-obj="${kerneldir}"
		./copy-builtin "${kerneldir}"
		sudo make "$CTHREADS"
		sudo make install

	fi

	# WireGuard VPN for Linux 3.10 - 5.5
	if linux-version compare "${version}" ge 3.10 && linux-version compare "${version}" le 5.5 && [ "${WIREGUARD}" == yes ]; then

		# attach to specifics tag or branch
		local wirever="branch:master"

		display_alert "Adding" "WireGuard VPN for Linux 3.10 - 5.5 ${wirever} " "info"
		fetch_from_repo "https://git.zx2c4.com/wireguard-linux-compat" "wireguard" "${wirever}" "yes"

		cd "$kerneldir" || exit
		rm -rf "$kerneldir/net/wireguard"
		cp -R "${SRC}/cache/sources/wireguard/${wirever#*:}/src/" "$kerneldir/net/wireguard"
		sed -i "/^obj-\\\$(CONFIG_NETFILTER).*+=/a obj-\$(CONFIG_WIREGUARD) += wireguard/" \
		"$kerneldir/net/Makefile"
		sed -i "/^if INET\$/a source \"net/wireguard/Kconfig\"" \
		"$kerneldir/net/Kconfig"
		# remove duplicates
		[[ $(grep -c wireguard "$kerneldir/net/Makefile") -gt 1 ]] && \
		sed -i '0,/wireguard/{/wireguard/d;}' "$kerneldir/net/Makefile"
		[[ $(grep -c wireguard "$kerneldir/net/Kconfig") -gt 1 ]] && \
		sed -i '0,/wireguard/{/wireguard/d;}' "$kerneldir/net/Kconfig"
		# headers workaround
		display_alert "Patching WireGuard" "Applying workaround for headers compilation" "info"
		sed -i '/mkdir -p "$destdir"/a mkdir -p "$destdir"/net/wireguard; \
		touch "$destdir"/net/wireguard/{Kconfig,Makefile} # workaround for Wireguard' \
		"$kerneldir/scripts/package/builddeb"

	fi


	# Updated USB network drivers for RTL8152/RTL8153 based dongles that also support 2.5Gbs variants

	if linux-version compare "${version}" ge 5.4 && [ $LINUXFAMILY != mvebu64 ] && [ $LINUXFAMILY != rk322x ] && [ $LINUXFAMILY != odroidxu4 ] && [ $EXTRAWIFI == yes ]; then

		# attach to specifics tag or branch
		local rtl8152ver="branch:master"

		display_alert "Adding" "Drivers for 2.5Gb RTL8152/RTL8153 USB dongles ${rtl8152ver}" "info"
		fetch_from_repo "https://github.com/igorpecovnik/realtek-r8152-linux" "rtl8152" "${rtl8152ver}" "yes"
		cp -R "${SRC}/cache/sources/rtl8152/${rtl8152ver#*:}"/{r8152.c,compatibility.h} \
		"$kerneldir/drivers/net/usb/"

	fi

	# Wireless drivers for Realtek 8189ES chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8189esver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8189ES chipsets ${rtl8189esver}" "info"

		fetch_from_repo "https://github.com/jwrdegoede/rtl8189ES_linux" "rtl8189es" "${rtl8189esver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189es"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189es/"
		cp -R "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8189es"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8189es/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189es/${rtl8189esver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8189es/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189ES) += rtl8189es/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189es\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Realtek 8189FS chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8189fsver="branch:rtl8189fs"

		display_alert "Adding" "Wireless drivers for Realtek 8189FS chipsets ${rtl8189fsver}" "info"

		fetch_from_repo "https://github.com/jwrdegoede/rtl8189ES_linux" "rtl8189fs" "${rtl8189fsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8189fs"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8189fs/"
		cp -R "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8189fs"

		# Makefile
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8189fs/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8189fs/${rtl8189fsver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8189fs/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8189FS) += rtl8189fs/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8189fs\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Realtek 8192EU chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8192euver="branch:realtek-4.4.x"

		display_alert "Adding" "Wireless drivers for Realtek 8192EU chipsets ${rtl8192euver}" "info"

		fetch_from_repo "https://github.com/Mange/rtl8192eu-linux-driver" "rtl8192eu" "${rtl8192euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8192eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8192eu/"
		cp -R "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8192eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8192eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8192eu/${rtl8192euver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8192eu/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8192EU) += rtl8192eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8192eu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8812auver="branch:v5.6.4.2"

		display_alert "Adding" "Wireless drivers for Realtek 8811, 8812, 8814 and 8821 chipsets ${rtl8812auver}" "info"

		fetch_from_repo "https://github.com/aircrack-ng/rtl8812au" "rtl8812au" "${rtl8812auver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8812au"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8812au/"
		cp -R "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8812au"

		# Makefile
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8812au/Makefile"

		# Kconfig
		cp "${SRC}/cache/sources/rtl8812au/${rtl8812auver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8812au/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_88XXAU) += rtl8812au/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8812au\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Xradio XR819 chipsets
	if linux-version compare "${version}" ge 4.19 && [[ "$LINUXFAMILY" == sunxi* ]] && [[ "$EXTRAWIFI" == yes ]]; then

		display_alert "Adding" "Wireless drivers for Xradio XR819 chipsets" "info"

		fetch_from_repo "https://github.com/karabek/xradio" "xradio" "branch:master" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/xradio"
		mkdir -p "$kerneldir/drivers/net/wireless/xradio/"
		cp "${SRC}"/cache/sources/xradio/master/*.{h,c} \
		"$kerneldir/drivers/net/wireless/xradio/"

		# Makefile
		cp "${SRC}/cache/sources/xradio/master/Makefile" \
		"$kerneldir/drivers/net/wireless/xradio/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/xradio/master/Kconfig"
		cp "${SRC}/cache/sources/xradio/master/Kconfig" \
		"$kerneldir/drivers/net/wireless/xradio/Kconfig"

		# Add to section Makefile
		echo "obj-\$(CONFIG_WLAN_VENDOR_XRADIO) += xradio/" \
		>> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/xradio\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8811cuver="commit:2bebdb9a35c1d9b6e6a928e371fa39d5fcec8a62"

		display_alert "Adding" "Wireless drivers for Realtek RTL8811CU and RTL8821C chipsets ${rtl8811cuver}" "info"

		fetch_from_repo "https://github.com/brektrou/rtl8821CU" "rtl8811cu" "${rtl8811cuver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8811cu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8811cu/"
		cp -R "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}"/{core,hal,include,os_dep,platform,rtl8821c.mk} \
		"$kerneldir/drivers/net/wireless/rtl8811cu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8811cu/${rtl8811cuver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Address ARM related bug https://github.com/aircrack-ng/rtl8812au/issues/233
		sed -i "s/^CONFIG_MP_VHT_HW_TX_MODE.*/CONFIG_MP_VHT_HW_TX_MODE = n/" \
		"$kerneldir/drivers/net/wireless/rtl8811cu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8821CU) += rtl8811cu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8811cu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

		# add support for K5.11+
		process_patch_file "${SRC}/patch/misc/wireless-rtl8811cu.patch" "applying"

	fi




	# Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8188euver="branch:v5.7.6.1"

		display_alert "Adding" "Wireless drivers for Realtek 8188EU 8188EUS and 8188ETV chipsets ${rtl8188euver}" "info"

		fetch_from_repo "https://github.com/aircrack-ng/rtl8188eus" "rtl8188eu" "${rtl8188euver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8188eu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8188eu/"
		cp -R "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8188eu"

		# Makefile
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8188eu/${rtl8188euver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8188eu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8188EU) += rtl8188eu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8188eu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

		process_patch_file "${SRC}/patch/misc/wireless-rtl8188eu.patch" "applying"

	fi




	# Wireless drivers for Realtek 88x2bu chipsets

	if linux-version compare "${version}" ge 3.14 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl88x2buver="branch:5.6.1_30362.20181109_COEX20180928-6a6a"

		display_alert "Adding" "Wireless drivers for Realtek 88x2bu chipsets ${rtl88x2buver}" "info"

		fetch_from_repo "https://github.com/cilynx/rtl88x2bu" "rtl88x2bu" "${rtl88x2buver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl88x2bu"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl88x2bu/"
		cp -R "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}"/{core,hal,include,os_dep,platform,halmac.mk,rtl8822b.mk} \
		"$kerneldir/drivers/net/wireless/rtl88x2bu"

		# Makefile
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl88x2bu/${rtl88x2buver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Kconfig"

		# Adjust path
		sed -i 's/include $(src)\/rtl8822b.mk /include $(TopDIR)\/drivers\/net\/wireless\/rtl88x2bu\/rtl8822b.mk/' \
		"$kerneldir/drivers/net/wireless/rtl88x2bu/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8822BU) += rtl88x2bu/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl88x2bu\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

	fi




	# Wireless drivers for Realtek 8723DS chipsets

	if linux-version compare "${version}" ge 5.0 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8723dsver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8723DS chipsets ${rtl8723dsver}" "info"

		fetch_from_repo "https://github.com/lwfinger/rtl8723ds" "rtl8723ds" "${rtl8723dsver}" "yes"
		cd "$kerneldir" || exit
		rm -rf "$kerneldir/drivers/net/wireless/rtl8723ds"
		mkdir -p "$kerneldir/drivers/net/wireless/rtl8723ds/"
		cp -R "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}"/{core,hal,include,os_dep,platform} \
		"$kerneldir/drivers/net/wireless/rtl8723ds"

		# Makefile
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Makefile" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Kconfig
		sed -i 's/---help---/help/g' "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig"
		cp "${SRC}/cache/sources/rtl8723ds/${rtl8723dsver#*:}/Kconfig" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Kconfig"

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		"$kerneldir/drivers/net/wireless/rtl8723ds/Makefile"

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DS) += rtl8723ds/" >> "$kerneldir/drivers/net/wireless/Makefile"
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723ds\/Kconfig"' \
		"$kerneldir/drivers/net/wireless/Kconfig"

                # add support for K5.11+
                process_patch_file "${SRC}/patch/misc/wireless-rtl8723ds.patch" "applying"

	fi




	# Wireless drivers for Realtek 8723DU chipsets

	if linux-version compare $version ge 5.0 && [ "$EXTRAWIFI" == yes ]; then

		# attach to specifics tag or branch
		local rtl8723duver="branch:master"

		display_alert "Adding" "Wireless drivers for Realtek 8723DU chipsets ${rtl8723duver}" "info"

		fetch_from_repo "https://github.com/lwfinger/rtl8723du" "rtl8723du" "${rtl8723duver}" "yes"
		cd $kerneldir
		rm -rf $kerneldir/drivers/net/wireless/rtl8723du
		mkdir -p $kerneldir/drivers/net/wireless/rtl8723du/
		cp -R ${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}/{core,hal,include,os_dep,platform} \
		$kerneldir/drivers/net/wireless/rtl8723du

		# Makefile
		cp ${SRC}/cache/sources/rtl8723du/${rtl8723duver#*:}/Makefile \
		$kerneldir/drivers/net/wireless/rtl8723du/Makefile

		# Disable debug
		sed -i "s/^CONFIG_RTW_DEBUG.*/CONFIG_RTW_DEBUG = n/" \
		$kerneldir/drivers/net/wireless/rtl8723du/Makefile

		# Add to section Makefile
		echo "obj-\$(CONFIG_RTL8723DU) += rtl8723du/" >> $kerneldir/drivers/net/wireless/Makefile
		sed -i '/source "drivers\/net\/wireless\/ti\/Kconfig"/a source "drivers\/net\/wireless\/rtl8723du\/Kconfig"' \
		$kerneldir/drivers/net/wireless/Kconfig

		process_patch_file "${SRC}/patch/misc/wireless-rtl8723du.patch" "applying"
	fi


	if linux-version compare $version ge 4.4 && linux-version compare $version lt 5.8; then
		display_alert "Adjusting" "Framebuffer driver for ST7789 IPS display" "info"
		process_patch_file "${SRC}/patch/misc/fbtft-st7789v-invert-color.patch" "applying"
	fi

}
