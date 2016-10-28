#!/bin/bash
#
# Copyright (c) 2014 Igor Pecovnik, igor.pecovnik@gma**.com
#
# www.igorpecovnik.com / images + support
#
# NAND, eMMC, SATA and USB Armbian installer
# nand boot za a10: git clone -b dev/a10-nand-ext4 https://github.com/mmplayer/u-boot-sunxi --depth 1
# Should work with: Cubietruck, Cubieboards, BananaPi, Olimex Lime+Lime2+Micro, Hummingboard, ...
#

# Import:
# DIR: path to u-boot directory
# write_uboot_platform: function to write u-boot to a block device
[[ -f /usr/lib/u-boot/platform_install.sh ]] && source /usr/lib/u-boot/platform_install.sh

# script configuration
CWD="/usr/lib/nand-sata-install"
EX_LIST="${CWD}/exclude.txt"
nanddevice="/dev/nand"

# read in board info
[[ -f /etc/armbian-release ]] && source /etc/armbian-release
backtitle="Armbian for $BOARD_NAME install script, http://www.armbian.com | Author: Igor Pecovnik"
title="NAND, eMMC, SATA and USB Armbian installer v""$VERSION"

# exception
if cat /proc/cpuinfo | grep -q 'sun4i'; then DEVICE_TYPE="a10"; else DEVICE_TYPE="a20"; fi
BOOTLOADER="${CWD}/${DEVICE_TYPE}/bootloader"

# find targets: NAND, EMMC, SATA
nandcheck=$(ls -l /dev/ | grep -w 'nand' | awk '{print $NF}');
[[ -n $nandcheck ]] && nandcheck="/dev/$nandcheck"
emmccheck=$(ls -l /dev/ | grep -w 'mmcblk[1-9]' | awk '{print $NF}');
[[ -n $emmccheck ]] && emmccheck="/dev/$emmccheck"
satacheck=$(cat /proc/partitions | grep  'sd' | awk '{print $NF}')

# Create boot and root file system $1 = boot, $2 = root (Example: create_armbian "/dev/nand1" "/dev/sda3")
create_armbian()
{
	# create mount points, mount and clean
	sync &&	mkdir -p /mnt/bootfs /mnt/rootfs
	[[ -n $2 ]] && mount $2 /mnt/rootfs
	[[ -n $1 ]] && mount $1 /mnt/bootfs
	rm -rf /mnt/bootfs/* /mnt/rootfs/*

	# sata root part
	# UUID=xxx...
	satauuid=$(blkid -o export $2 | grep -w UUID)

	# SD card boot part
	# UUID=xxx...
	sduuid=$(blkid -o export /dev/mmcblk0p1 | grep -w UUID)

	# calculate usage and see if it fits on destination
	USAGE=$(df -BM | grep ^/dev | head -1 | awk '{print $3}' | tr -cd '[0-9]. \n')
	DEST=$(df -BM | grep ^/dev | grep /mnt/rootfs | awk '{print $4}' | tr -cd '[0-9]. \n')	
	if [[ $USAGE -gt $DEST ]]; then
		dialog --title "$title" --backtitle "$backtitle"  --colors --infobox\
		"\n\Z1Partition too small.\Zn Needed: $USAGE Mb Avaliable: $DEST Mb" 5 60
		umountdevice "$1"; umountdevice "$2"
		exit 1
	fi

	if [[ $1 == *nand* ]]; then
		# creating nand boot. Copy precompiled uboot
		rsync -aqc $BOOTLOADER/* /mnt/bootfs
	fi

	# count files is needed for progress bar
	dialog --title "$title" --backtitle "$backtitle" --infobox "\n  Counting files ... few seconds." 5 40
	TODO=$(rsync -ahvrltDn --delete --stats --exclude-from=$EX_LIST / /mnt/rootfs | grep "Number of files:"|awk '{print $4}' | tr -d '.,')

	# creating rootfs
	rsync -avrltD  --delete --exclude-from=$EX_LIST / /mnt/rootfs | nl | awk '{ printf "%.0f\n", 100*$1/"'"$TODO"'" }' \
	| dialog --backtitle "$backtitle"  --title "$title" --gauge "\n\n  Creating rootfs on $2 ($USAGE Mb). Please wait!" 10 80

	# run rsync again to silently catch outstanding changes between / and /mnt/rootfs/
	dialog --title "$title" --backtitle "$backtitle" --infobox "\n  Cleaning up ... few seconds." 5 40
	rsync -avrltD  --delete --exclude-from=$EX_LIST / /mnt/rootfs >/dev/null 2>&1

	# creating fstab from scratch
	rm -f /mnt/rootfs/etc/fstab

	# creating fstab, kernel and boot script for NAND partition
	if [[ $1 == *nand* ]]; then
		REMOVESDTXT="and remove SD to boot from NAND"
		#sed -i '/boot/d' /mnt/rootfs/etc/fstab
		echo "$1 /boot vfat	defaults 0 0" >> /mnt/rootfs/etc/fstab
		echo "$2 / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1" >> /mnt/rootfs/etc/fstab
		dialog --title "$title" --backtitle "$backtitle" --infobox "\nConverting kernel ... few seconds." 5 60
		mkimage -A arm -O linux -T kernel -C none -a "0x40008000" -e "0x40008000" -n "Linux kernel" -d \
			/boot/zImage /mnt/bootfs/uImage >/dev/null 2>&1
		cp /boot/script.bin /mnt/bootfs/

		# Note: Not using UUID based boot for NAND
		cat <<-EOF > /mnt/bootfs/uEnv.txt
		console=ttyS0,115200
		root=$2 rootwait
		extraargs="console=tty1 hdmi.audio=EDID:0 disp.screen0_output_mode=EDID:0 consoleblank=0 loglevel=1"
		EOF

		sync

		[[ $DEVICE_TYPE = a20 ]] && echo "machid=10bb" >> /mnt/bootfs/uEnv.txt
		# ugly hack becouse we don't have sources for A10 nand uboot
		if [[ $ID == Cubieboard || $BOARD_NAME == Cubieboard || $ID == "Lime A10" || $BOARD_NAME == "Lime A10" ]]; then
			cp /mnt/bootfs/uEnv.txt /mnt/rootfs/boot/uEnv.txt
			cp /mnt/bootfs/script.bin /mnt/rootfs/boot/script.bin
			cp /mnt/bootfs/uImage /mnt/rootfs/boot/uImage
		fi
		umountdevice "/dev/nand"
		tune2fs -o journal_data_writeback /dev/nand2 >/dev/null 2>&1
		tune2fs -O ^has_journal /dev/nand2 >/dev/null 2>&1
		e2fsck -f /dev/nand2 >/dev/null 2>&1

	elif [[ $2 == ${emmccheck}p1 || $1 == ${emmccheck}p1 ]]; then

		# fix that we can have one exlude file
		cp -R /boot/ /mnt/bootfs

		# eMMC install
		# old boot scripts
		
		sed -e 's,root='"$root_partition"',root='"$emmcuuid"',g' -i /mnt/bootfs/boot/boot.cmd
		# new boot scripts
		if [[ -f /mnt/bootfs/boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$emmcuuid"',g' -i /mnt/bootfs/boot/armbianEnv.txt			
		else
			sed -e 's,setenv rootdev.*,setenv rootdev '"$emmcuuid"',g' -i /mnt/bootfs/boot/boot.cmd			
		fi
		mkimage -C none -A arm -T script -d /mnt/bootfs/boot/boot.cmd /mnt/bootfs/boot/boot.scr	>/dev/null 2>&1 || (echo "Error"; exit 0)

		# fstab adj
		echo "$emmcuuid / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1" > /mnt/rootfs/etc/fstab

		if [[ $(type -t write_uboot_platform) != function ]]; then
			echo "Error: no u-boot package found, exiting"
			exit -1
		fi

		write_uboot_platform $DIR $emmccheck

	elif [[ -f /boot/boot.cmd ]]; then
		# old boot scripts
		sed -e 's,root='"$root_partition"',root='"$satauuid"',g' -i /boot/boot.cmd
		# new boot scripts
		if [[ -f /boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$satauuid"',g' -i  /boot/armbianEnv.txt
		else
			sed -e 's,setenv rootdev.*,setenv rootdev '"$satauuid"',g' -i /boot/boot.cmd
		fi
		mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr >/dev/null 2>&1 || (echo "Error"; exit 0)
		mkdir -p /mnt/rootfs/media/mmc/boot
		echo "$sduuid        /media/mmc   ext4    defaults        0       0" >> /mnt/rootfs/etc/fstab
		echo "/media/mmc/boot   /boot   none    bind        0       0" >> /mnt/rootfs/etc/fstab
		echo "$satauuid / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1" >> /mnt/rootfs/etc/fstab
	elif [[ -f /boot/boot.ini ]]; then
		# old boot scripts		
		sed -e 's,root='"$root_partition"',root='"$satauuid"',g' -i /boot/boot.ini
		# new boot scripts
		if [[ -f /boot/armbianEnv.txt ]]; then
			sed -e 's,rootdev=.*,rootdev='"$satauuid"',g' -i  /boot/armbianEnv.txt
		else
			sed -e 's,setenv rootdev.*,setenv rootdev '"$satauuid"',g' -i /boot/boot.ini
		fi
		mkdir -p /mnt/rootfs/media/mmc/boot
		echo "$sduuid        /media/mmc   ext4    defaults        0       0" >> /mnt/rootfs/etc/fstab
		echo "/media/mmc/boot   /boot   none    bind        0       0" >> /mnt/rootfs/etc/fstab		
		echo "$satauuid / ext4 defaults,noatime,nodiratime,commit=600,errors=remount-ro 0 1" >> /mnt/rootfs/etc/fstab		
	fi	
	echo "tmpfs /tmp tmpfs defaults,nosuid 0 0" >> /mnt/rootfs/etc/fstab
	cat /etc/fstab  | grep swap >> /mnt/rootfs/etc/fstab
	umountdevice "/dev/sda"
} # create_armbian

# Accept device as parameter: for example /dev/sda unmounts all their mounts
umountdevice()
{
	if [[ -n $1 ]]; then
		device=$1;
		for n in ${device}*; do
			if [[ $device != "$n" ]]; then
				if mount|grep -q ${n}; then
					umount -l $n >/dev/null 2>&1
				fi
			fi
		done
	fi
} # umountdevice

# Recognize root filesystem
recognize_root()
{
	# replace with PARTUUID approach parsing /proc/cmdline when ready
	local device="/dev/"$(lsblk -idn -o NAME | grep mmcblk0)
	local partitions=$(($(fdisk -l $device | grep $device | wc -l)-1))
	local device="/dev/"$(lsblk -idn -o NAME | grep mmcblk0)"p"$partitions
	local root_device=$(mountpoint -d /)
	for file in /dev/* ; do
		local current_device=$(printf "%d:%d" $(stat --printf="0x%t 0x%T" $file))
		if [[ $current_device = $root_device ]]; then
			root_partition=$file
			break;
		fi
	done
} # recognize_root

# Formatting NAND - no parameters. Fixed solution.
formatnand()
{
	[[ ! -e /dev/nand ]] && echo "NAND error" && exit 0
	dialog --title "$title" --backtitle "$backtitle"  --infobox "\nFormating ... up to one minute." 5 40
	if [[ $DEVICE_TYPE = a20 ]]; then
		(echo y;) | sunxi-nand-part -f a20 /dev/nand 65536 'bootloader 65536' 'linux 0' >/dev/null 2>&1
	else
		(echo y;) | sunxi-nand-part -f a10 /dev/nand 65536 'bootloader 65536' 'linux 0' >/dev/null 2>&1
	fi
	mkfs.vfat /dev/nand1 >/dev/null 2>&1
	mkfs.ext4 /dev/nand2 >/dev/null 2>&1
} # formatnand

# Formatting eMMC [device] example /dev/mmcblk1
formatemmc()
{
	# deletes all partitions
	dialog --title "$title" --backtitle "$backtitle"  --infobox "\n  Formating eMMC ... one moment." 5 40
	dd bs=1 seek=446 count=64 if=/dev/zero of=$1 >/dev/null 2>&1
	# calculate capacity and reserve some unused space to ease cloning of the installation
	# to other media 'of the same size' (one sector less and cloning will fail)
	QUOTED_DEVICE=$(echo "${1}" | sed 's:/:\\\/:g')
	CAPACITY=$(parted ${1} unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", \$2 / ( 1024 / \$4 ))}")

	if [[ $CAPACITY -lt 4000000 ]]; then
		# Leave 2 percent unpartitioned when eMMC size is less than 4GB (unlikely)
		LASTSECTOR=$(( 32 * $(parted ${1} unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", ( \$2 * 98 / 3200))}") -1 ))
	else
		# Leave 1 percent unpartitioned
		LASTSECTOR=$(( 32 * $(parted ${1} unit s print -sm | awk -F":" "/^${QUOTED_DEVICE}/ {printf (\"%0d\", ( \$2 * 99 / 3200))}") -1 ))
	fi

	parted -s $1 -- mklabel msdos
	parted -s $1 -- mkpart primary ext4 2048s ${LASTSECTOR}s
	partprobe $1
	# create fs
	mkfs.ext4 -qF $1"p1" >/dev/null 2>&1
	emmcuuid=$(blkid -o export $1"p1" | grep -w UUID)
} # formatemmc

# formatting SATA/USB [device] example /dev/sda3
formatsata()
{
	dialog --title "$title" --backtitle "$backtitle"  --infobox "\nFormating ... up to one minute." 5 40
	mkfs.ext4 $1 >/dev/null 2>&1
	tune2fs $1 -o journal_data_writeback >/dev/null 2>&1
} # formatsata

# choose target SATA/USB partition.
checksatatarget()
{
	IFS=" "
	SataTargets=$(awk '/sd/ {print "/dev/"$4}' </proc/partitions | grep -E '[0-9]{1,4}' | nl | xargs echo -n)
	if [[ -z $SataTargets ]]; then
		dialog --title "$title" --backtitle "$backtitle"  --colors --infobox \
		"\n\Z1There are no avaliable partitions. Please create them.\Zn" 5 60
		exit 1
	fi

	SataOptions=($SataTargets)
	SataCmd=(dialog --title "Select destination:" --backtitle "$backtitle" --menu "\n$infos" 10 60 16)
	SataChoices=$("${SataCmd[@]}" "${SataOptions[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1
	SDA_ROOT_PART=${SataOptions[(2*$SataChoices)-1]}
} # checksatatarget

# show warning [TEXT]
ShowWarning()
{
	dialog --title "$title" --backtitle "$backtitle" --cr-wrap --colors --yesno " \Z1$(toilet -f mono12 WARNING)\Zn\n$1" 17 74
	[[ $? -ne 0 ]] && exit 1
} # ShowWarning

main()
{
	export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

	# This tool must run under root

	if [[ $EUID -ne 0 ]]; then
		echo "This tool must run as root. Exiting ..."
		exit 1
	fi

	# Check if we run it from SD card

	if [[ $(sed -n 's/^DEVNAME=//p' /sys/dev/block/$(mountpoint -d /)/uevent) != mmcblk* ]]; then
		dialog --title "$title" --backtitle "$backtitle"  --colors --infobox "\n\Z1This tool must run from SD-card!\Zn" 5 42
		exit 1
	fi

	#recognize_root
	root_partition=$(cat /proc/cmdline | sed -e 's/^.*root=//' -e 's/ .*$//')
	IFS="'"
	options=()
	if [[ -n $emmccheck ]]; then
		ichip="eMMC";
		dest_boot=$emmccheck"p1"
		dest_root=$emmccheck"p1"
	else
		ichip="NAND"
		dest_boot="/dev/nand1"
		dest_root="/dev/nand2"
	fi

	[[ -n $nandcheck || -n $emmccheck ]] && options=(${options[@]} 1 'Boot from '$ichip' - system on '$ichip)
	[[ ( -n $nandcheck || -n $emmccheck ) && -n $satacheck ]] && options=(${options[@]} 2 'Boot from '$ichip' - system on SATA or USB')
	[[ -n $satacheck ]] && options=(${options[@]} 3 'Boot from SD   - system on SATA or USB')

	[[ ${#options[@]} -eq 0 || "$root_partition" == "$emmcuuid" || "$root_partition" == "/dev/nand2" ]] && dialog --title "$title" --backtitle "$backtitle"  --colors --infobox "\n\Z1There are no targets. Please check your drives.\Zn" 5 60 && exit 1

	cmd=(dialog --title "Choose an option:" --backtitle "$backtitle" --menu "\nCurrent root: $root_partition \n \n" 14 60 7)
	choices=$("${cmd[@]}" "${options[@]}" 2>&1 >/dev/tty)
	[[ $? -ne 0 ]] && exit 1

	for choice in $choices
	do
		case $choice in
			1)
				title="$ichip install"
				command="Power off"
				ShowWarning "This script will erase your $ichip. Continue?"
				if [[ -n $emmccheck ]]; then
					umountdevice "$emmccheck"
					formatemmc "$emmccheck"
				else
					umountdevice "/dev/nand"
					formatnand
				fi
				create_armbian "$dest_boot" "$dest_root"
				;;
			2)
				title="$ichip boot / SATA root install"
				command="Power off"
				checksatatarget
				ShowWarning "This script will erase your $ichip and $SDA_ROOT_PART. Continue?"
				if [[ -n $emmccheck ]]; then
					umountdevice "$emmccheck"
					formatemmc "$emmccheck"
					else
					umountdevice "/dev/nand"
					formatnand
				fi
				umountdevice "${SDA_ROOT_PART//[0-9]*/}"
				formatsata "$SDA_ROOT_PART"
				create_armbian "$dest_boot" "$SDA_ROOT_PART"
				;;
			3)
				title="SD boot / SATA root install"
				command="Reboot"
				checksatatarget
				ShowWarning "This script will erase your device $SDA_ROOT_PART. Continue?"
				formatsata "$SDA_ROOT_PART"
				create_armbian "" "$SDA_ROOT_PART"
				;;
		esac
	done

	dialog --title "$title" --backtitle "$backtitle"  --yes-label "$command" --no-label "Exit" --yesno "\nAll done. $command $REMOVESDTXT" 7 60
	[[ $? -eq 0 ]] && "$(echo ${command,,} | sed 's/ //')"
} # main

main "$@"
