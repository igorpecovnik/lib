# install custom xorg for pinebook-pro
cp -R "${SRC}"/packages/bsp/pinebook-pro/xorg.conf "${destination}"/etc/X11/xorg.conf.d/

# install custom asound state for pinebook-pro
cp -R "${SRC}"/packages/asound.state/ "${destination}"/etc/

## touchpad and keyboard tweaks
# from https://github.com/ayufan-rock64/linux-package/tree/master/root-pinebookpro
cp $SRC/packages/bsp/pinebook-pro/40-pinebookpro-touchpad.conf $destination/etc/X11/xorg.conf.d/
mkdir -p $destination/etc/udev/hwdb.d/
cp $SRC/packages/bsp/pinebook-pro/10-usb-kbd.hwdb $destination/etc/udev/hwdb.d/
