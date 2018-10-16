# DO NOT EDIT THIS FILE
#
# Please edit /boot/armbianEnv.txt to set supported parameters
#

setenv ramdisk_addr_r "0x21000000"
setenv overlay_error "false"
# default values
setenv rootdev "/dev/mmcblk0p1"
setenv verbosity "1"
setenv console "both"
setenv rootfstype "ext4"
setenv docker_optimizations "on"

if test -e ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}armbianEnv.txt; then
	load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}armbianEnv.txt
	env import -t ${ramdisk_addr_r} ${filesize}
fi

if test "${logo}" = "disabled"; then setenv logo "logo.nologo"; fi

# Tinkerboard walkaround.
if test "${console}" = "ttyS2,115200n8"; then setenv console "both"; fi
if test "${console}" = "display" || test "${console}" = "both"; then setenv consoleargs "console=tty1"; fi
if test "${console}" = "serial" || test "${console}" = "both"; then setenv consoleargs "console=ttyS2,115200n8 ${consoleargs}"; fi

# get PARTUUID of first partition on SD/eMMC the boot script was loaded from
if test "${devtype}" = "mmc"; then part uuid mmc ${devnum}:1 partuuid; fi

setenv bootargs "earlyprintk root=${rootdev} rootwait rootfstype=${rootfstype} ${consoleargs} panic=10 consoleblank=0 loglevel=${verbosity} ubootpart=${partuuid} usb-storage.quirks=${usbstoragequirks} ${extraargs} ${extraboardargs}"

if test "${docker_optimizations}" = "on"; then setenv bootargs "${bootargs} cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory swapaccount=1"; fi

if test "${board}" = "miqi_rk3288"; then setenv fdtfile "rk3288-miqi.dtb"; fi

load ${devtype} ${devnum} ${ramdisk_addr_r} ${prefix}uInitrd
load ${devtype} ${devnum} ${kernel_addr_r} ${prefix}zImage
load ${devtype} ${devnum} ${fdt_addr_r} ${prefix}dtb/${fdtfile}

bootz ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}

# Recompile with:
# mkimage -C none -A arm -T script -d /boot/boot.cmd /boot/boot.scr
