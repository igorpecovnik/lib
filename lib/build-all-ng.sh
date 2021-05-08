#!/bin/bash
#
# Copyright (c) Authors: http://www.armbian.com/authors
#
# This file is licensed under the terms of the GNU General Public
# License version 2. This program is licensed "as is" without any
# warranty of any kind, whether express or implied.

# This file is a part of the Armbian build script
# https://github.com/armbian/build/

# Functions:
# pack_upload
# build_main
# array_contains
# build_all




if [[ $BETA == "yes" ]];  then STABILITY="beta";	else STABILITY="stable"; fi
if [[ $BETA == "yes" ]]; then upload_subdir=nightly; else upload_subdir="archive"; fi
if [[ $MAKE_ALL_BETA == "yes" ]]; then STABILITY="stable"; fi
if [[ -z $KERNEL_ONLY ]]; then KERNEL_ONLY="yes"; fi
if [[ -z $MULTITHREAD ]]; then MULTITHREAD=0; fi
if [[ -z $START ]]; then START=0; fi
if [[ -z $KERNEL_CONFIGURE ]]; then KERNEL_CONFIGURE="no"; fi
if [[ -z $CLEAN_LEVEL ]]; then CLEAN_LEVEL="make,oldcache"; fi

MAINLINE_KERNEL_SOURCE='https://kernel.googlesource.com/pub/scm/linux/kernel/git/stable/linux-stable'

# cleanup
rm -f /run/armbian/*.pid
mkdir -p /run/armbian

# read user defined targets if exits
if [[ -f $USERPATCHES_PATH/targets.conf ]]; then

	display_alert "Adding user provided targets configuration"
	BUILD_TARGETS="${USERPATCHES_PATH}/targets.conf"

else

	BUILD_TARGETS="${SRC}/config/targets.conf"

fi

unset_all ()
{
unset	LINUXFAMILY LINUXCONFIG KERNELDIR KERNELSOURCE KERNELBRANCH BOOTDIR BOOTSOURCE BOOTBRANCH ARCH UBOOT_USE_GCC \
		KERNEL_USE_GCC CPUMIN CPUMAX UBOOT_VER KERNEL_VER GOVERNOR BOOTSIZE BOOTFS_TYPE UBOOT_TOOLCHAIN KERNEL_TOOLCHAIN \
		DEBOOTSTRAP_LIST PACKAGE_LIST_EXCLUDE KERNEL_IMAGE_TYPE write_uboot_platform family_tweaks family_tweaks_bsp \
		setup_write_uboot_platform uboot_custom_postprocess atf_custom_postprocess family_tweaks_s BOOTSCRIPT \
		UBOOT_TARGET_MAP LOCALVERSION UBOOT_COMPILER KERNEL_COMPILER BOOTCONFIG BOOTCONFIG_VAR_NAME INITRD_ARCH BOOTENV_FILE BOOTDELAY \
		ATF_TOOLCHAIN2 MOUNT SDCARD BOOTPATCHDIR KERNELPATCHDIR RELEASE IMAGE_TYPE OVERLAY_PREFIX ASOUND_STATE ATF_COMPILER \
		ATF_USE_GCC ATFSOURCE ATFDIR ATFBRANCH ATFSOURCEDIR PACKAGE_LIST_RM NM_IGNORE_DEVICES DISPLAY_MANAGER \
		family_tweaks_bsp_s CRYPTROOT_ENABLE CRYPTROOT_PASSPHRASE CRYPTROOT_SSH_UNLOCK CRYPTROOT_SSH_UNLOCK_PORT \
		CRYPTROOT_SSH_UNLOCK_KEY_NAME ROOT_MAPPER NETWORK HDMI USB WIRELESS ARMBIANMONITOR FORCE_BOOTSCRIPT_UPDATE \
		UBOOT_TOOLCHAIN2 toolchain2 BUILD_REPOSITORY_URL BUILD_REPOSITORY_COMMIT BUILD_TARGET HOST BUILD_IMAGE \
		DEB_STORAGE REPO_STORAGE REPO_CONFIG REPOSITORY_UPDATE PACKAGE_LIST_RELEASE LOCAL_MIRROR COMPILE_ATF \
		PACKAGE_LIST_BOARD PACKAGE_LIST_FAMILY PACKAGE_LIST_DESKTOP_BOARD PACKAGE_LIST_DESKTOP_FAMILY ATF_COMPILE ATFPATCHDIR OFFSET BOOTSOURCEDIR BOOT_USE_BLOBS \
		BOOT_SOC DDR_BLOB MINILOADER_BLOB BL31_BLOB BOOT_RK3328_USE_AYUFAN_ATF BOOT_USE_BLOBS BOOT_RK3399_LEGACY_HYBRID \
		BOOT_USE_MAINLINE_ATF BOOT_USE_TPL_SPL_BLOB BOOT_SUPPORT_SPI OFFLINE_WORK IMAGE_PARTITION_TABLE BOOT_LOGO UPSTREM_VER FORCED_MONTH_OFFSET \
		PACKAGE_LIST_BOARD_REMOVE PACKAGE_LIST_FAMILY_REMOVE PACKAGE_LIST_DESKTOP_BOARD_REMOVE PACKAGE_LIST_DESKTOP_FAMILY_REMOVE BOOTCONFIG_EDGE \
		DESKTOP_ENVIRONMENT DESKTOP_ENVIRONMENT_CONFIG_NAME DESKTOP_APPGROUPS_SELECTED DESKTOP_APT_FLAGS_SELECTED \
		DESKTOP_ENVIRONMENT_DIRPATH DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH DESKTOP_ENVIRONMENT_DIRPATH DESKTOP_ENVIRONMENT_PACKAGE_LIST_DIRPATH \
		DESKTOP_CONFIG_PREFIX DESKTOP_CONFIGS_DIR DESKTOP_APPGROUPS_DIR DEBIAN_RECOMMENDS USE_OVERLAYFS aggregated_content DEBOOTSTRAP_COMPONENTS
}

pack_upload ()
{

	# pack and upload to server or just pack

	display_alert "Signing" "Please wait!" "info"
	local version="Armbian_${REVISION}_${BOARD^}_${RELEASE}_${BRANCH}_${VER/-$LINUXFAMILY/}${DESKTOP_ENVIRONMENT:+_$DESKTOP_ENVIRONMENT}"
	compression_type=""

	[[ $BUILD_DESKTOP == yes ]] && version=${version}_desktop
	[[ $BUILD_MINIMAL == yes ]] && version=${version}_minimal
	[[ $BETA == yes ]] && local subdir=nightly

	cd "${DESTIMG}" || exit

	if [[ $COMPRESS_OUTPUTIMAGE == yes ]]; then
		COMPRESS_OUTPUTIMAGE="sha,gpg,7z"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gz* ]]; then
		display_alert "Compressing" "$DEST/images/${version}.img.gz" "info"
		pigz "$DESTIMG/${version}.img"
		rm "${DESTIMG}/${version}.img"
		compression_type=".gz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *xz* ]]; then
		display_alert "Compressing" "$DEST/images/${version}.img.xz" "info"
		pixz -9 < "$DESTIMG/${version}.img" > "${DESTIMG}/${version}.img.xz"
		rm "${DESTIMG}/${version}.img"
		compression_type=".xz"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *sha* ]]; then
		display_alert "SHA256 calculating" "${version}.img" "info"
		sha256sum -b "${version}.img${compression_type}" > "${version}.img${compression_type}.sha"
	fi

	if [[ $COMPRESS_OUTPUTIMAGE == *gpg* ]]; then
		if [[ -n $GPG_PASS ]]; then
			display_alert "GPG signing" "${version}.img" "info"
			echo "${GPG_PASS}" | gpg --passphrase-fd 0 --armor --detach-sign --pinentry-mode loopback --batch --yes "${version}.img${compression_type}" || exit 1
		else
			display_alert "GPG signing skipped - no GPG_PASS" "${version}.img" "wrn"
		fi
	fi

	fingerprint_image "${version}.img${compression_type}.txt" "${version}"

	if [[ $COMPRESS_OUTPUTIMAGE == *7z* ]]; then
		display_alert "Compressing" "${version}.7z" "info"
		7za a -t7z -bd -m0=lzma2 -mx=3 -mfb=64 -md=32m -ms=on "${version}".7z "${version}".img* >/dev/null 2>&1
		find . -type f -not -name '*.7z' -print0 | xargs -0 rm --
	fi

	if [[ -n "${SEND_TO_SERVER}" ]]; then
		ssh "${SEND_TO_SERVER}" "mkdir -p ${SEND_TO_LOCATION}${BOARD}/{archive,nightly}" &
		display_alert "Uploading" "Please wait!" "info"
		nice -n 19 bash -c "rsync -arP --info=progress2 --prune-empty-dirs $DESTIMG/ -e 'ssh -T -c aes128-ctr -o Compression=no -x -p 22' ${SEND_TO_SERVER}:${SEND_TO_LOCATION}${BOARD}/${subdir}; rm -rf ${DESTIMG}/*" &
	else
		mv "${DESTIMG}"/*.* "${DEST}"/images/
	fi

}




build_main ()
{
	# shellcheck source=/dev/null
	source "$USERPATCHES_PATH"/lib.config
	# build images which we do pack or kernel
	local upload_image
	upload_image="Armbian_$(cat "${SRC}"/VERSION)_${BOARD^}_${RELEASE}_${BRANCH}_*${VER/-$LINUXFAMILY/}"

	[[ $BUILD_DESKTOP == yes ]] && upload_image=${upload_image}_desktop
	[[ $BUILD_MINIMAL == yes ]] && upload_image=${upload_image}_minimal

	touch "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${DESKTOP_ENVIRONMENT}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid";

	if [[ $KERNEL_ONLY != yes ]]; then
		#if ssh ${SEND_TO_SERVER} stat ${SEND_TO_LOCATION}${BOARD}/${upload_subdir}/${upload_image}* \> /dev/null 2\>\&1; then
		#	echo "$n exists $upload_image"
		#else
			#shellcheck source=lib/main.sh
			source "${SRC}"/lib/main.sh
			[[ "$BSP_BUILD" != yes && -n "${SEND_TO_SERVER}" ]] && pack_upload
		#fi

	else
		#shellcheck source=lib/main.sh
		source "${SRC}"/lib/main.sh

	fi

	cd "${SRC}"
	rm "/run/armbian/Armbian_${BOARD^}_${BRANCH}_${RELEASE}_${DESKTOP_ENVIRONMENT}_${BUILD_DESKTOP}_${BUILD_MINIMAL}.pid"
}




array_contains ()
{

	# utility snippet

	local array="$1[@]"
	local seeking=$2
	local in=1

	for element in "${!array}"; do
		if [[ "${element}" == "${seeking}" ]]; then
			in=0
			break
		fi
	done
	return $in

}




function check_hash()
{
	local BOARDFAMILY ref_type ref_name

	BOARDFAMILY=$(grep BOARDFAMILY "${SRC}/config/boards/${BOARD}".* | cut -d \" -f2)
	# shellcheck source=/dev/null
	source "${SRC}/config/sources/families/${BOARDFAMILY}.conf"
	# shellcheck source=/dev/null
	source "${SRC}/config/sources/${ARCH}.conf"
	ref_type=${KERNELBRANCH%%:*}
	if [[ $ref_type == head ]]; then
		ref_name=HEAD
	else
		ref_name=${KERNELBRANCH##*:}
	fi
	[[ -z $LINUXFAMILY ]] && LINUXFAMILY=$BOARDFAMILY
	[[ -z ${KERNELPATCHDIR} ]] && KERNELPATCHDIR=$LINUXFAMILY-$BRANCH
	[[ -z ${LINUXCONFIG} ]] && LINUXCONFIG=linux-$LINUXFAMILY-$BRANCH
	hash_watch_1=$(find "${SRC}/patch/kernel/${KERNELPATCHDIR}"/ -maxdepth 1 -printf '%s %P\n' 2> /dev/null | sort)
	hash_watch_2=$(cat "${SRC}/config/kernel/${LINUXCONFIG}.config" 2> /dev/null)
	patch_hash=$(echo "${hash_watch_1}${hash_watch_2}" | improved_git hash-object --stdin)

	case $ref_type in
		branch) hash=$(improved_git ls-remote "${KERNELSOURCE}" refs/heads/"${ref_name}" 2> /dev/null | awk '{print $1}') ;;
		tag) hash=$(improved_git ls-remote "${KERNELSOURCE}" tags/"${ref_name}" 2> /dev/null | awk '{print $1}') ;;
		head) hash=$(improved_git ls-remote "${KERNELSOURCE}" HEAD 2> /dev/null | awk '{print $1}') ;;
		commit) hash=$ref_name ;;
	esac
	# ignore diff checking in case of network errrors
	local kernel_hash="${SRC}/cache/hash"$([[ ${BETA} == yes ]] && echo "-beta")"/linux-image-${BRANCH}-${LINUXFAMILY}.githash"
	if [[ -f ${kernel_hash} ]]; then
		[[ "$hash" == "$(head -1 "${kernel_hash}")" && "$patch_hash" == "$(tail -1 "${kernel_hash}")" || -z $hash ]] && echo "idential"
	fi
}




function build_all()
{

	# main routine

	buildall_start=$(date +%s)
	n=0
	ARRAY=()
	buildlist="cat "

	# building selected ones
	if [[ -n ${REBUILD_IMAGES} ]]; then

		buildlist="grep -w '"
		filter="'"
		for build in $(tr ',' ' ' <<< "${REBUILD_IMAGES}"); do
				buildlist=$buildlist"$build\|"
				filter=$filter"$build\|"
		done
		buildlist=${buildlist::-2}"'"
		filter=${filter::-2}"'"

	fi

	# find unique boards - we will build debs for all variants
	sorted_unique_ids=($(echo "${ids[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
	unique_boards=$(eval "${buildlist}" "${SRC}"/config/targets.conf | sed '/^#/ d' | awk '{print $1}')
	read -r -a unique_boards <<< "$(echo "${unique_boards[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')"

	while read -r line; do

		[[ "${line}" =~ ^#.*$ ]] && continue
		[[ -n "${REBUILD_IMAGES}" ]] && [[ -z $(echo "${line}" | eval grep -w "${filter}") ]] && continue
		#[[ $n -lt $START ]] && ((n+=1)) && continue

		unset_all
		# unset also board related variables
		unset BOARDFAMILY DESKTOP_AUTOLOGIN DEFAULT_CONSOLE FULL_DESKTOP MODULES MODULES_CURRENT MODULES_LEGACY MODULES_EDGE \
		BOOTCONFIG MODULES_BLACKLIST MODULES_BLACKLIST_LEGACY MODULES_BLACKLIST_CURRENT MODULES_BLACKLIST_EDGE DEFAULT_OVERLAYS SERIALCON \
		BUILD_MINIMAL RELEASE ATFBRANCH BOOT_FDT_FILE BOOTCONFIG_EDGE BOOTSOURCEDIR SRC_CMDLINE SRC_EXTLINUX

		read -r BOARD BRANCH RELEASE BUILD_TARGET BUILD_STABILITY BUILD_IMAGE DESKTOP_ENVIRONMENT DESKTOP_ENVIRONMENT_CONFIG_NAME DESKTOP_APPGROUPS_SELECTED<<< "${line}"
		DESKTOP_APPGROUPS_SELECTED="${DESKTOP_APPGROUPS_SELECTED//,/ }"
		# read all possible configurations
		# shellcheck source=/dev/null
		source "${SRC}/config/boards/${BOARD}".eos 2> /dev/null
		# shellcheck source=/dev/null
		source "${SRC}/config/boards/${BOARD}".tvb 2> /dev/null
		# shellcheck source=/dev/null
		source "${SRC}/config/boards/${BOARD}".csc 2> /dev/null
		# shellcheck source=/dev/null
		source "${SRC}/config/boards/${BOARD}".wip 2> /dev/null
		# shellcheck source=/dev/null
		source "${SRC}/config/boards/${BOARD}".conf 2> /dev/null

		# override branch to build selected branches if defined
		if [[ -n "${BROVER}" ]]; then
			if [[ "${KERNEL_TARGET}" == *${BROVER}* ]]; then
				BRANCH=${BROVER}
			else
				continue
			fi
		fi

		# exceptions handling
		[[ ${BOARDFAMILY} == sun*i ]] && BOARDFAMILY=sunxi
		[[ ${BOARDFAMILY} == sun*iw* ]] && BOARDFAMILY=sunxi64
		[[ ${BOARDFAMILY} == meson8b ]] && BOARDFAMILY=meson
		[[ ${BOARDFAMILY} == meson-* ]] && BOARDFAMILY=meson64

		# small optimisation. we only (try to) build needed kernels
		if [[ $KERNEL_ONLY == yes ]]; then
			LINUXFAMILY="${BOARDFAMILY}"
			array_contains ARRAY "${LINUXFAMILY}${BRANCH}${BUILD_STABILITY}" && continue

		elif [[ $BUILD_IMAGE == no ]] ; then

			continue

		fi
		ARRAY+=("${LINUXFAMILY}${BRANCH}${BUILD_STABILITY}")

		BUILD_DESKTOP="no"
		BUILD_MINIMAL="no"

		[[ ${BUILD_TARGET} == "desktop" && ${BSP_BUILD} != "yes" ]] && BUILD_DESKTOP="yes"
		[[ ${BUILD_TARGET} == "minimal" ]] && BUILD_MINIMAL="yes"
		[[ ${BSP_BUILD} == yes ]] && BUILD_STABILITY=$STABILITY

		# create beta or stable
		if [[ "${BUILD_STABILITY}" == "${STABILITY}" ]]; then
			# check if currnt hash is the same as upstream
			if [[ "$IGNORE_HASH" != yes ]]; then
				local store_hash
				store_hash=$(check_hash)
			fi
			if [[ "$store_hash" != idential ]]; then

			if [[ $1 != "dryrun" ]] && [[ $n -ge $START ]]; then
					((n+=1))
						while :
							do
							if [[ $(find /run/armbian/*.pid 2>/dev/null | wc -l) -le ${MULTITHREAD} || ${MULTITHREAD} -eq 0  ]]; then
								break
							fi
							sleep 5
							done

					display_alert "Building ${n}."
					if [[ "$KERNEL_ONLY" == "no" && "${MULTITHREAD}" -gt 0 ]]; then
						build_main &
						sleep $((RANDOM % 25))
					elif [[ "${MULTITHREAD}" -gt 0 ]]; then
						build_main &
						sleep $((RANDOM % 5))
					else
						build_main
					fi

			# create BSP for all boards
			elif [[ "${BSP_BUILD}" == yes ]]; then
				((n+=1))
				for BOARD in "${unique_boards[@]}"
				do
					# shellcheck source=/dev/null
					source "${SRC}/config/boards/${BOARD}".eos 2> /dev/null
					# shellcheck source=/dev/null
					source "${SRC}/config/boards/${BOARD}".tvb 2> /dev/null
					# shellcheck source=/dev/null
					source "${SRC}/config/boards/${BOARD}".csc 2> /dev/null
					# shellcheck source=/dev/null
					source "${SRC}/config/boards/${BOARD}".wip 2> /dev/null
					# shellcheck source=/dev/null
					source "${SRC}/config/boards/${BOARD}".conf 2> /dev/null
					IFS=',' read -r -a RELBRANCH <<< "${KERNEL_TARGET}"
					for BRANCH in "${RELBRANCH[@]}"
					do
					RELTARGETS=(xenial stretch buster bullseye bionic focal hirsute sid)
					# we don't need to cycle all distributions when making u-boot package
					[[ $BOOTONLY == "yes" ]] && RELTARGETS=(focal)
					for RELEASE in "${RELTARGETS[@]}"
					do
						display_alert "BSP for ${BOARD} ${BRANCH} ${RELEASE}."
						if [[ "$IGNORE_HASH" == yes && "$KERNEL_ONLY" != "yes" && "${MULTITHREAD}" -gt 0 ]]; then
							build_main &
							sleep 0.02
						elif [[ "${MULTITHREAD}" -gt 0 ]]; then
							build_main &
							sleep $((RANDOM % 5))
						else
							build_main
						fi
						# unset non board related stuff
						unset_all
					done
					done
				done
				display_alert "Done building all BSP images"
				exit
			else
				((n+=1))
				# In dryrun it only prints out what will be build but also color green if file already exists
				FIND="$SRC/output/images/$BOARD/$upload_subdir/Armbian_$(cat "${SRC}"/VERSION)_${BOARD^}_${RELEASE}_${BRANCH}"
				if ls $FIND* 1> /dev/null 2>&1; then
					echo -ne "\e[0;92m"
				else
					echo -ne "\x1B[0m"
				fi
				printf "%s\t%-32s\t%-8s\t%-14s\t%-6s\t%-6s\t%-6s\t%-6s\n" "${n}." \
				"$BOARD (${BOARDFAMILY})" "${BRANCH}" "${RELEASE}" "${DESKTOP_ENVIRONMENT}" "${BUILD_DESKTOP}" "${BUILD_MINIMAL}" "${DESKTOP_APPGROUPS_SELECTED}"
			fi
		fi
		fi

	# at which image to stop
	[[ "$STOP" == "$n" ]] && [[ $1 != "dryrun" ]] && exit
	done < "${BUILD_TARGETS}"

}

# bump version in case there was a change
if [[ ${BUMP_VERSION} == yes ]]; then

        cd "${SRC}" || exit
        CURRENT_VERSION=$(cat VERSION)
        NEW_VERSION="${CURRENT_VERSION%%-trunk}"
        if [[ $CURRENT_VERSION == *trunk* ]]; then
                NEW_VERSION=$(echo "${CURRENT_VERSION}" | cut -d. -f1-3)"."$((${NEW_VERSION##*.} + 1))
        else
                NEW_VERSION=$(echo "${CURRENT_VERSION}" | cut -d. -f1-2)"."$((${NEW_VERSION##*.} + 1))
        fi

        echo "${NEW_VERSION}" > VERSION
        improved_git add "${SRC}"/VERSION
        improved_git commit -m "Bumping to new version" -m "" -m "Adding following kernels:" -m "$(find output/debs-beta/ -type f -name "linux-image*${CURRENT_VERSION}*.deb" -printf "%f\n" | sort)"
        improved_git push
        display_alert "Bumping to new version" "${NEW_VERSION}" "info"

else

# display what will be build
echo ""
display_alert "Building all targets" "$STABILITY $(if [[ $KERNEL_ONLY == "yes" ]] ; then echo "kernels"; \
else echo "images"; fi)" "info"

printf "\n%s\t%-32s\t%-8s\t%-14s\t%-6s\t%-6s\t%-6s\t%-6s\n\n" "" "board" "branch" "release" "DE" "desktop" "minimal" "DE app groups"

# display what we will build
build_all "dryrun"

if [[ $BUILD_ALL != demo ]] ; then

	echo ""
	# build
	build_all

fi

# wait until they are not finshed
sleep 5
while :
do
		if [[ $(df | grep -c /.tmp) -lt 1 ]]; then
			break
		fi
	sleep 5
done

while :
do
		if [[ -z $(ps -uax | grep 7z | grep Armbian) ]]; then
			break
		fi
	sleep 5
done

# display what we will build
build_all "dryrun"

fi

[[ $n -eq 0 ]] && display_alert "No changes in upstream sources, patches or configs found. Exiting." "info"

buildall_end=$(date +%s)
buildall_runtime=$(((buildall_end - buildall_start) / 60))
display_alert "Runtime in total" "${buildall_runtime} min" "info"
echo "${n}" > "${SRC}"/.tmp/n
