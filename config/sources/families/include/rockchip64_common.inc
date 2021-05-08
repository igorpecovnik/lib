ARCH=arm64
KERNEL_IMAGE_TYPE=Image
OFFSET=16
BOOTSCRIPT='boot-rockchip64.cmd:boot.cmd'
BOOTENV_FILE='rockchip.txt'
UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
BOOTDELAY=0
OVERLAY_PREFIX='rockchip'
SERIALCON=${SERIALCON:=$([ $BRANCH == "legacy" ] && echo "ttyFIQ0:1500000" || echo "ttyS2:1500000")}
GOVERNOR="ondemand"
BOOTBRANCH="tag:v2021.01"
PACKAGE_LIST_FAMILY="ethtool"

RKBIN_DIR="$SRC/cache/sources/rkbin-tools"

if [[ $BOOTCONFIG == *3399* ]]; then

	CPUMIN=${CPUMIN:="408000"}
	CPUMAX=${CPUMAX:="2016000"}

else # rk3308, rk3328

	CPUMIN=${CPUMIN:="408000"}
	CPUMAX=${CPUMAX:="1296000"}

fi

if [[ $BOARD == nanopi-r2s || $BOARD == nanopineo3 || $BOARD == orangepi-r1plus || $BOARD == renegade || $BOARD == rockpi-e || $BOARD == station-m1 || $BOARD == z28pro ]]; then

	BOOT_USE_BLOBS=yes
	BOOT_SOC=rk3328
	DDR_BLOB='rk33/rk3328_ddr_333MHz_v1.16.bin'
	MINILOADER_BLOB='rk33/rk322xh_miniloader_v2.50.bin'
	BL31_BLOB='rk33/rk322xh_bl31_v1.44.elf'

elif [[ $BOARD == rock64 ]]; then

	BOOT_USE_MAINLINE_ATF=yes
	BOOT_SOC=rk3328

elif [[ $BOOTCONFIG == *3328* ]]; then

	BOOT_RK3328_USE_AYUFAN_ATF=yes

elif [[ $BOARD == pinebook-pro ]]; then

	BOOT_USE_MAINLINE_ATF=yes
	BOOT_SOC=rk3399
	ATFPATCHDIR='atf-rk3399'

elif [[ $BOARD == rockpi-4* ]]; then

	BOOT_USE_BLOBS=yes
	BOOT_SUPPORT_SPI=yes
	BOOT_SOC=rk3399
	DDR_BLOB='rk33/rk3399_ddr_933MHz_v1.20.bin' # 1GB model does not boot with later versions
	MINILOADER_BLOB='rk33/rk3399_miniloader_v1.19.bin'
	BL31_BLOB='rk33/rk3399_bl31_v1.30.elf'

elif [[ $BOARD == station-p1 ]]; then

	BOOT_USE_BLOBS=yes
	BOOT_SUPPORT_SPI=yes
	BOOT_SOC=rk3399
	DDR_BLOB='rk33/rk3399_ddr_933MHz_v1.24.bin'
	MINILOADER_BLOB='rk33/rk3399_miniloader_v1.19.bin'
	BL31_BLOB='rk33/rk3399_bl31_v1.30.elf'

elif [[ $BOARD == rockpro64 ]]; then

	BOOT_USE_TPL_SPL_BLOB=yes
	BOOT_SUPPORT_SPI=yes
	BOOT_SOC=rk3399
	BL31_BLOB='rk33/rk3399_bl31_v1.30.elf'

elif [[ $BOARD == rockpi-s ]]; then

	BOOT_USE_BLOBS=yes
	BOOT_SOC=rk3308
	DDR_BLOB='rk33/rk3308_ddr_589MHz_uart0_m0_v1.26.bin'
	MINILOADER_BLOB='rk33/rk3308_miniloader_sd_nand_v1.13.bin'
	BL31_BLOB='rk33/rk3308_bl31_v2.10.elf'

else

	ATFPATCHDIR='atf-rk3399'

fi

case $BRANCH in

	current)

		KERNELPATCHDIR='rockchip64-'$BRANCH
		KERNELBRANCH="branch:linux-5.10.y"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

	edge)

		KERNELPATCHDIR='rockchip64-'$BRANCH
		KERNELBRANCH="branch:linux-5.11.y"
		LINUXFAMILY=rockchip64
		LINUXCONFIG='linux-rockchip64-'$BRANCH

	;;

esac

prepare_boot_configuration()
{
	if [[ $BOOT_USE_MAINLINE_ATF == yes ]]; then

		UBOOT_TARGET_MAP="BL31=bl31.bin idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE='https://github.com/ARM-software/arm-trusted-firmware'
		ATF_COMPILER='aarch64-linux-gnu-'
		ATFDIR='arm-trusted-firmware'
		ATFBRANCH='tag:v2.2'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP="M0_CROSS_COMPILE=arm-linux-gnueabi- PLAT=$BOOT_SOC bl31;;build/$BOOT_SOC/release/bl31/bl31.elf:bl31.bin"
		ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"

	elif [[ $BOOT_USE_TPL_SPL_BLOB == yes ]]; then

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB idbloader.img u-boot.itb;;idbloader.img u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_USE_BLOBS == yes ]]; then

		UBOOT_TARGET_MAP="u-boot-dtb.bin;;idbloader.bin uboot.img trust.bin"
		ATFSOURCE=''
		ATF_COMPILE='no'

	elif [[ $BOOT_RK3399_LEGACY_HYBRID == yes ]]; then # to be removed

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB u-boot-dtb.bin spl/u-boot-spl.bin u-boot.itb;;spl/u-boot-spl.bin u-boot.itb"
		ATFSOURCE=''
		ATF_COMPILE='no'

		legacy_uboot_locations

	elif [[ $BOOT_RK3328_USE_AYUFAN_ATF == yes ]]; then # to be removed

		UBOOT_TARGET_MAP=";;idbloader.bin uboot.img trust.bin"
		ATFSOURCE='https://github.com/ayufan-rock64/arm-trusted-firmware'
		ATF_COMPILER='aarch64-linux-gnu-'
		ATFDIR='arm-trusted-firmware-rockchip64'
		ATFBRANCH='branch:rockchip'
		ATF_USE_GCC='> 6.3'
		ATF_TARGET_MAP='PLAT=rk322xh DEBUG=1 bl31;;trust.bin'
		ATF_TOOLCHAIN2="arm-linux-gnueabi-:> 5.0"

		legacy_uboot_locations

	fi

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then

		UBOOT_TARGET_MAP="BL31=$RKBIN_DIR/$BL31_BLOB tpl/u-boot-tpl.bin spl/u-boot-spl.bin u-boot.itb ${UBOOT_TARGET_MAP} rkspi_loader.img"

	fi
}

legacy_uboot_locations()
{
	BOOTSOURCE='https://github.com/ayufan-rock64/linux-u-boot'
	BOOTDIR='u-boot-rockchip64'
	BOOTBRANCH='branch:rockchip-master'
	case $BRANCH in
		legacy)
			BOOTPATCHDIR="u-boot-rockchip64"
			;;
		*)
			BOOTPATCHDIR="u-boot-rockchip64-dev"
			;;
	esac
}

uboot_custom_postprocess()
{
	if [ "$(uname -m)" = "aarch64" ]; then
		if [ "$(lsb_release -sc)" = "focal" ]; then
			PKG_PREFIX="qemu-x86_64-static -L /usr/x86_64-linux-gnu "
		else
			PKG_PREFIX="qemu-x86_64 -L /usr/x86_64-linux-gnu "
		fi
	else
		PKG_PREFIX=""
	fi

	RKBIN_DIR="$SRC/cache/sources/rkbin-tools"

	if [[ $BOOT_USE_MAINLINE_ATF == yes || $BOOT_USE_TPL_SPL_BLOB == yes ]]; then
		:
	elif [[ $BOOT_USE_BLOBS == yes ]]; then

		local tempfile=$(mktemp)
		tools/mkimage -n $BOOT_SOC -T rksd -d $RKBIN_DIR/$DDR_BLOB idbloader.bin
		cat $RKBIN_DIR/$MINILOADER_BLOB >> idbloader.bin
		$PKG_PREFIX$RKBIN_DIR/tools/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000
		$PKG_PREFIX$RKBIN_DIR/tools/trust_merger --replace bl31.elf $RKBIN_DIR/$BL31_BLOB trust.ini

	elif [[ $BOOT_RK3399_LEGACY_HYBRID == yes ]]; then

		# 3399
		tools/mkimage -n rk3399 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3399_ddr_933MHz_v1.13.bin rksd_loader.img
		cat spl/u-boot-spl.bin >> rksd_loader.img
		dd if=u-boot.itb of=rksd_loader.img seek=448 conv=notrunc
		cp rksd_loader.img $SRC/.tmp/$uboot_name/usr/lib/$uboot_name/$f_dst
		tools/mkimage -n rk3399 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3399_ddr_933MHz_v1.13.bin rkspi_loader.img
		cat spl/u-boot-spl.bin >> rkspi_loader.img
		for i in `seq 1 128`; do dd count=4 status=none; dd if=/dev/zero count=4 status=none; done < rkspi_loader.img > rkspi_loader.tmp
		mv rkspi_loader.tmp rkspi_loader.img
		dd if=u-boot.itb of=rkspi_loader.img seek=1024 conv=notrunc
		cp rkspi_loader.img $SRC/.tmp/$uboot_name/usr/lib/$uboot_name/$f_dst

	elif [[ $BOOT_RK3328_USE_AYUFAN_ATF == yes ]]; then

		# 3328
		tools/mkimage -n rk3328 -T rksd -d $SRC/cache/sources/rkbin-tools/rk33/rk3328_ddr_786MHz_v1.13.bin idbloader.bin
		cat $SRC/cache/sources/rkbin-tools/rk33/rk3328_miniloader_v2.46.bin >> idbloader.bin
		$PKG_PREFIX$RKBIN_DIR/tools/loaderimage --pack --uboot ./u-boot-dtb.bin uboot.img 0x200000

	else
		echo "Unsupported u-boot processing configuration!"
		exit 1
	fi

	if [[ $BOOT_SUPPORT_SPI == yes ]]; then
		tools/mkimage -n $BOOT_SOC -T rkspi -d tpl/u-boot-tpl.bin:spl/u-boot-spl.bin rkspi_tpl_spl.img
		dd if=/dev/zero of=rkspi_loader.img count=8128 status=none
		dd if=rkspi_tpl_spl.img of=rkspi_loader.img conv=notrunc status=none
		dd if=u-boot.itb of=rkspi_loader.img seek=768 conv=notrunc status=none
	fi
}

write_uboot_platform()
{
	if [[ -f $1/rksd_loader.img ]]; then # legacy rk3399 loader

		dd if=$1/rksd_loader.img of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1

	elif [[ -f $1/u-boot.itb ]]; then # $BOOT_USE_MAINLINE_ATF == yes || $BOOT_USE_TPL_SPL_BLOB == yes

		dd if=$1/idbloader.img of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/u-boot.itb of=$2 seek=16384 conv=notrunc status=none >/dev/null 2>&1

	elif [[ -f $1/uboot.img ]]; then # $BOOT_USE_BLOBS == yes

		dd if=$1/idbloader.bin of=$2 seek=64 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/uboot.img of=$2 seek=16384 conv=notrunc status=none >/dev/null 2>&1
		dd if=$1/trust.bin of=$2 seek=24576 conv=notrunc status=none >/dev/null 2>&1

	else
		echo "Unsupported u-boot processing configuration!"
		exit 1

	fi
}

write_uboot_platform_mtd()
{
	if [[ -f $1/rkspi_loader.img ]]; then

		dd if=$1/rkspi_loader.img of=$2 conv=notrunc status=none >/dev/null 2>&1

	else

		echo "SPI u-boot image not found!"
		exit 1

	fi
}

setup_write_uboot_platform()
{

	if grep -q "ubootpart" /proc/cmdline; then

		local tmp=$(cat /proc/cmdline)
		tmp="${tmp##*ubootpart=}"
		tmp="${tmp%% *}"
		[[ -n $tmp ]] && local part=$(findfs PARTUUID=$tmp 2>/dev/null)
		[[ -n $part ]] && local dev=$(lsblk -n -o PKNAME $part 2>/dev/null)
		[[ -n $dev ]] && DEVICE="/dev/$dev"

	fi

}


atf_custom_postprocess()
{

	# remove bl31.bin which can be 4+GiB in size and thus may fill the tmpfs mount
	rm -f build/rk322xh/debug/bl31.bin
	# ATF
	$PKG_PREFIX$RKBIN_DIR/tools/trust_merger trust.ini

}


family_tweaks()
{

	if [[ $BOARD == z28pro ]]; then

		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable z28pro-bluetooth.service >/dev/null 2>&1"

	elif [[ $BOARD == nanopi-r2s || $BOARD == orangepi-r1plus ]]; then

		# rename USB based network to lan0
		mkdir -p $SDCARD/etc/udev/rules.d/
		echo 'SUBSYSTEM=="net", ACTION=="add", DRIVERS=="r8152", KERNEL=="eth1", NAME="lan0"' > $SDCARD/etc/udev/rules.d/70-rename-lan.rules

	elif [[ $BOARD == helios64 ]]; then

		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable helios64-heartbeat-led.service >/dev/null 2>&1"

	elif [[ -f $SDCARD/lib/systemd/system/rk3399-bluetooth.service ]]; then

		# install and enable Bluetooth
		chroot $SDCARD /bin/bash -c "apt-get -y -qq install rfkill bluetooth bluez bluez-tools"
		chroot $SDCARD /bin/bash -c "systemctl --no-reload enable rk3399-bluetooth.service >/dev/null 2>&1"

	fi

	if [[ $BOARD == pinebook-pro ]]; then

                chroot $SDCARD /bin/bash -c "echo SuspandState=freeze >> /etc/systemd/sleep.conf"
                chroot $SDCARD /bin/bash -c "echo HandlePowerKey=ignore >> /etc/systemd/login.d"
	fi

}


family_tweaks_bsp()
{

	if [[ $BOOTCONFIG == *3328* ]] && [[ $BRANCH != legacy ]]; then
		mkdir -p "$destination"/etc/X11/xorg.conf.d
		cat <<-EOF > "$destination"/etc/X11/xorg.conf.d/02-driver.conf
		# set fbdev as default driver.
		Section "Device"
	         Identifier "NOGPU"
	         Driver "fbdev"
		EndSection
		EOF
	fi

	if [[ $BOARD == z28pro ]]; then

		mkdir -p $destination/usr/local/bin

		# Bluetooth for Z28 PRO
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/8822b_hciattach $destination/usr/bin
		install -m 755 $SRC/packages/bsp/rk3328/z28pro/start_bt.sh $destination/usr/local/bin
		cp $SRC/packages/bsp/rk3328/z28pro/z28pro-bluetooth.service $destination/lib/systemd/system/

	elif [[ $BRANCH == legacy && ($BOARD == rockpi-4[bc] || $BOARD == nanop*4* || $BOARD == orangepi* || $BOARD == firefly*) ]]; then

		# Bluetooth for most of others (custom patchram is needed only in legacy)
		install -m 755 $SRC/packages/bsp/rk3399/brcm_patchram_plus_rk3399 $destination/usr/bin
		cp $SRC/packages/bsp/rk3399/rk3399-bluetooth.service $destination/lib/systemd/system/

		if [[ $BOARD == nanop*4* || $BOARD == firefly* || $BOARD == orangepi-rk3399 ]]; then
			sed -i s%BCM4345C5%BCM4356A2%g $destination/lib/systemd/system/rk3399-bluetooth.service
		fi
	fi

	if [[ $BOARD == helios64 ]]; then

		mkdir -p $destination/etc/udev/rules.d/
		mkdir -p $destination/etc/systemd/system/fancontrol.service.d/
		mkdir -p $destination/lib/systemd/system/
		mkdir -p $destination/lib/systemd/system-shutdown/
		cp $SRC/packages/bsp/helios64/50-usb-realtek-net.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/70-keep-usb-lan-as-eth1.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/90-helios64-ups.rules $destination/etc/udev/rules.d/
		cp $SRC/packages/bsp/helios64/asound.conf $destination/etc/
		install -m 755 $SRC/packages/bsp/helios64/disable_auto_poweron $destination/lib/systemd/system-shutdown/

		### Fancontrol tweaks
		# copy hwmon rules to fix device mapping
		if [[ $BRANCH == legacy ]]; then
			install -m 644 $SRC/packages/bsp/helios64/90-helios64-hwmon-legacy.rules $destination/etc/udev/rules.d/
		else
			install -m 644 $SRC/packages/bsp/helios64/90-helios64-hwmon.rules $destination/etc/udev/rules.d/
		fi

		install -m 644 $SRC/packages/bsp/helios64/fancontrol.service.pid-override $destination/etc/systemd/system/fancontrol.service.d/pid.conf

		# copy fancontrol config
		install -m 644 $SRC/packages/bsp/helios64/fancontrol.conf $destination/etc/fancontrol

		# LED tweak
		if [[ $BRANCH == legacy ]]; then
			install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led-legacy.service $destination/etc/systemd/system/helios64-heartbeat-led.service
		else
			install -m 644 $SRC/packages/bsp/helios64/helios64-heartbeat-led.service $destination/etc/systemd/system/
		fi

		# UPS service
		cp $SRC/packages/bsp/helios64/helios64-ups.service $destination/lib/systemd/system/
		cp $SRC/packages/bsp/helios64/helios64-ups.timer $destination/lib/systemd/system/
		install -m 755 $SRC/packages/bsp/helios64/helios64-ups.sh $destination/usr/bin/helios64-ups.sh

	fi

	# Graphics and media
	mkdir -p $destination/etc/udev/rules.d
	cp $SRC/packages/bsp/rk3399/50-mali.rules $destination/etc/udev/rules.d/
	cp $SRC/packages/bsp/rk3399/50-rk3399-vpu.rules $destination/etc/udev/rules.d/
	mkdir -p $destination/etc/sysfs.d
	cp $SRC/packages/bsp/rk3399/20-gpu-governor.conf $destination/etc/sysfs.d/

}
