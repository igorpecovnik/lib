# install custom asound state for pinebook-pro
mkdir -p "${destination}"/etc/
cp -R "${SRC}"/packages/blobs/asound.state/ "${destination}"/etc/

# install custom xorg for pinebook-pro
mkdir -p "${destination}"/etc/X11/
cp -R "${SRC}"/packages/bsp/rk3399/xorg.conf "${destination}"/etc/X11/
