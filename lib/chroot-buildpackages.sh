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
# create_chroot
# chroot_prepare_distccd
# chroot_build_packages
# chroot_installpackages_local
# chroot_installpackages

# create_chroot <target_dir> <release> <arch>
#
create_chroot()
{
	local target_dir="$1"
	local release=$2
	local arch=$3
	declare -A qemu_binary apt_mirror components
	qemu_binary['armhf']='qemu-arm-static'
	qemu_binary['arm64']='qemu-aarch64-static'
	apt_mirror['stretch']="$DEBIAN_MIRROR"
	apt_mirror['buster']="$DEBIAN_MIRROR"
	apt_mirror['bullseye']="$DEBIAN_MIRROR"
	apt_mirror['xenial']="$UBUNTU_MIRROR"
	apt_mirror['bionic']="$UBUNTU_MIRROR"
	apt_mirror['focal']="$UBUNTU_MIRROR"
	apt_mirror['groovy']="$UBUNTU_MIRROR"
	apt_mirror['hirsute']="$UBUNTU_MIRROR"
	components['stretch']='main,contrib'
	components['buster']='main,contrib'
	components['bullseye']='main,contrib'
	components['sid']='main,contrib'
	components['xenial']='main,universe,multiverse'
	components['bionic']='main,universe,multiverse'
	components['focal']='main,universe,multiverse'
	components['groovy']='main,universe,multiverse'
	components['hirsute']='main,universe,multiverse'
	display_alert "Creating build chroot" "$release/$arch" "info"
	local includes="ccache,locales,git,ca-certificates,devscripts,libfile-fcntllock-perl,debhelper,rsync,python3,distcc"
	# perhaps a temporally workaround
	[[ $release == buster || $release == bullseye || $release == focal || $release == groovy || $release == hirsute || $release == sid ]] && includes=${includes}",perl-openssl-defaults,libnet-ssleay-perl"
	if [[ $NO_APT_CACHER != yes ]]; then
		local mirror_addr="http://localhost:3142/${apt_mirror[${release}]}"
	else
		local mirror_addr="http://${apt_mirror[${release}]}"
	fi
	debootstrap --variant=buildd --components="${components[${release}]}" --arch="${arch}" $DEBOOTSTRAP_OPTION --foreign --include="${includes}" "${release}" "${target_dir}" "${mirror_addr}"
	[[ $? -ne 0 || ! -f "${target_dir}"/debootstrap/debootstrap ]] && exit_with_error "Create chroot first stage failed"
	cp /usr/bin/${qemu_binary[$arch]} "${target_dir}"/usr/bin/
	[[ ! -f "${target_dir}"/usr/share/keyrings/debian-archive-keyring.gpg ]] && \
		mkdir -p  "${target_dir}"/usr/share/keyrings/ && \
		cp /usr/share/keyrings/debian-archive-keyring.gpg "${target_dir}"/usr/share/keyrings/
	chroot "${target_dir}" /bin/bash -c "/debootstrap/debootstrap --second-stage"
	[[ $? -ne 0 || ! -f "${target_dir}"/bin/bash ]] && exit_with_error "Create chroot second stage failed"
	create_sources_list "$release" "${target_dir}"
	[[ $NO_APT_CACHER != yes ]] && \
		echo 'Acquire::http { Proxy "http://localhost:3142"; };' > "${target_dir}"/etc/apt/apt.conf.d/02proxy
	cat <<-EOF > "${target_dir}"/etc/apt/apt.conf.d/71-no-recommends
	APT::Install-Recommends "0";
	APT::Install-Suggests "0";
	EOF
	[[ -f "${target_dir}"/etc/locale.gen ]] && sed -i "s/^# en_US.UTF-8/en_US.UTF-8/" "${target_dir}"/etc/locale.gen
	chroot "${target_dir}" /bin/bash -c "locale-gen; update-locale LANG=en_US:en LC_ALL=en_US.UTF-8"
	printf '#!/bin/sh\nexit 101' > "${target_dir}"/usr/sbin/policy-rc.d
	chmod 755 "${target_dir}"/usr/sbin/policy-rc.d
	rm "${target_dir}"/etc/resolv.conf 2>/dev/null
	echo "nameserver $NAMESERVER" > "${target_dir}"/etc/resolv.conf
	rm "${target_dir}"/etc/hosts 2>/dev/null
	echo "127.0.0.1 localhost" > "${target_dir}"/etc/hosts
	mkdir -p "${target_dir}"/root/{build,overlay,sources} "${target_dir}"/selinux
	if [[ -L "${target_dir}"/var/lock ]]; then
		rm -rf "${target_dir}"/var/lock 2>/dev/null
		mkdir -p "${target_dir}"/var/lock
	fi
	chroot "${target_dir}" /bin/bash -c "/usr/sbin/update-ccache-symlinks"
	[[ $release == bullseye || $release == focal || $release == groovy || $release == hirsute || $release == sid ]] && chroot "${target_dir}" /bin/bash -c "ln -s /usr/bin/python3 /usr/bin/python"
	touch "${target_dir}"/root/.debootstrap-complete
	display_alert "Debootstrap complete" "${release}/${arch}" "info"
} #############################################################################


# chroot_prepare_distccd <release> <arch>
#
chroot_prepare_distccd()
{
	local release=$1
	local arch=$2
	local dest=/tmp/distcc/${release}-${arch}
	declare -A gcc_version gcc_type
	gcc_version['stretch']='6.3'
	gcc_version['buster']='8.3'
	gcc_version['bullseye']='9.2'
	gcc_version['xenial']='5.4'
	gcc_version['bionic']='5.4'
	gcc_version['focal']='9.2'
	gcc_version['groovy']='10.2'
	gcc_version['hirsute']='10.2'
	gcc_version['sid']='10.2'
	gcc_type['armhf']='arm-linux-gnueabihf-'
	gcc_type['arm64']='aarch64-linux-gnu-'
	rm -f "${dest}"/cmdlist
	mkdir -p "${dest}"
	local toolchain_path
	toolchain_path=$(find_toolchain "${gcc_type[${arch}]}" "== ${gcc_version[${release}]}")
	ln -sf "${toolchain_path}/${gcc_type[${arch}]}gcc" "${dest}"/cc
	echo "${dest}/cc" >> "${dest}"/cmdlist
	for compiler in gcc cpp g++ c++; do
		echo "${dest}/$compiler" >> "${dest}"/cmdlist
		echo "${dest}/${gcc_type[$arch]}${compiler}" >> "${dest}"/cmdlist
		ln -sf "${toolchain_path}/${gcc_type[${arch}]}${compiler}" "${dest}/${compiler}"
		ln -sf "${toolchain_path}/${gcc_type[${arch}]}${compiler}" "${dest}/${gcc_type[${arch}]}${compiler}"
	done
	mkdir -p /var/run/distcc/
	touch /var/run/distcc/"${release}-${arch}".pid
	chown -R distccd /var/run/distcc/
	chown -R distccd /tmp/distcc
}

# chroot_build_packages
#
chroot_build_packages()
{
	local built_ok=()
	local failed=()

	if [[ $IMAGE_TYPE == user-built ]]; then
		# if user-built image compile only for selected arch/release
		target_release="${RELEASE}"
		target_arch="${ARCH}"
	else
		# only make packages for recent releases. There are no changes on older
		target_release="stretch bionic buster bullseye groovy focal hirsute sid"
		target_arch="armhf arm64"
	fi

	for release in $target_release; do
		for arch in $target_arch; do
			display_alert "Starting package building process" "$release/$arch" "info"

			local target_dir
			target_dir="${SRC}/cache/buildpkg/${release}-${arch}-v${CHROOT_CACHE_VERSION}"
			local distcc_bindaddr="127.0.0.2"

			[[ ! -f "${target_dir}"/root/.debootstrap-complete ]] && create_chroot "${target_dir}" "${release}" "${arch}"
			[[ ! -f "${target_dir}"/root/.debootstrap-complete ]] && exit_with_error "Creating chroot failed" "${release}/${arch}"

			[[ -f /var/run/distcc/"${release}-${arch}".pid ]] && kill "$(<"/var/run/distcc/${release}-${arch}.pid")" > /dev/null 2>&1

			chroot_prepare_distccd "${release}" "${arch}"

			# DISTCC_TCP_DEFER_ACCEPT=0
			DISTCC_CMDLIST=/tmp/distcc/${release}-${arch}/cmdlist TMPDIR=/tmp/distcc distccd --daemon \
				--pid-file "/var/run/distcc/${release}-${arch}.pid" --listen $distcc_bindaddr --allow 127.0.0.0/24 \
				--log-file "/tmp/distcc/${release}-${arch}.log" --user distccd

			local t=$target_dir/root/.update-timestamp
			if [[ ! -f ${t} || $(( ($(date +%s) - $(<"${t}")) / 86400 )) -gt 7 ]]; then
				display_alert "Upgrading packages" "$release/$arch" "info"
				systemd-nspawn -a -q -D "${target_dir}" /bin/bash -c "apt-get -q update; apt-get -q -y upgrade; apt-get clean"
				date +%s > "${t}"
			fi

			for plugin in "${SRC}"/packages/extras-buildpkgs/*.conf; do
				unset package_name package_repo package_ref package_builddeps package_install_chroot package_install_target \
					package_upstream_version needs_building plugin_target_dir package_component "package_builddeps_${release}"
				source "${plugin}"

				# check build condition
				if [[ $(type -t package_checkbuild) == function ]] && ! package_checkbuild; then
					display_alert "Skipping building $package_name for" "$release/$arch"
					continue
				fi

				local plugin_target_dir=${DEB_STORAGE}/extra/$package_component/
				mkdir -p "${plugin_target_dir}"

				# check if needs building
				local needs_building=no
				if [[ -n $package_install_target ]]; then
					for f in $package_install_target; do
						if [[ -z $(find "${plugin_target_dir}" -name "${f}_*$REVISION*_$arch.deb") ]]; then
							needs_building=yes
							break
						fi
					done
				else
					needs_building=yes
				fi
				if [[ $needs_building == no ]]; then
					display_alert "Packages are up to date" "$package_name $release/$arch" "info"
					continue
				fi
				display_alert "Building packages" "$package_name $release/$arch" "ext"
				local dist_builddeps_name="package_builddeps_${release}"
				[[ -v $dist_builddeps_name ]] && package_builddeps="${package_builddeps} ${!dist_builddeps_name}"

				# create build script
				cat <<-EOF > "${target_dir}"/root/build.sh
				#!/bin/bash
				export PATH="/usr/lib/ccache:\$PATH"
				export HOME="/root"
				export DEBIAN_FRONTEND="noninteractive"
				export DEB_BUILD_OPTIONS="nocheck noautodbgsym"
				export CCACHE_TEMPDIR="/tmp"
				# distcc is disabled to prevent compilation issues due to different host and cross toolchain configurations
				#export CCACHE_PREFIX="distcc"
				# uncomment for debug
				#export CCACHE_RECACHE="true"
				#export CCACHE_DISABLE="true"
				export DISTCC_HOSTS="$distcc_bindaddr"
				export DEBFULLNAME="$MAINTAINER"
				export DEBEMAIL="$MAINTAINERMAIL"
				$(declare -f display_alert)
				cd /root/build
				if [[ -n "${package_builddeps}" ]]; then
					# can be replaced with mk-build-deps
					deps=()
					installed=\$(dpkg-query -W -f '\${db:Status-Abbrev}|\${binary:Package}\n' '*' 2>/dev/null | grep '^ii' | awk -F '|' '{print \$2}' | cut -d ':' -f 1)
					for packet in $package_builddeps; do grep -q -x -e "\$packet" <<< "\$installed" || deps+=("\$packet"); done
					if [[ \${#deps[@]} -gt 0 ]]; then
						display_alert "Installing build dependencies"
						apt-get -y -q update
						apt-get -y -q --no-install-recommends --show-progress -o DPKG::Progress-Fancy=1 install "\${deps[@]}"
					fi
				fi
				display_alert "Copying sources"
				rsync -aq /root/sources/"${package_name}" /root/build/
				cd /root/build/"${package_name}"
				# copy overlay / "debianization" files
				[[ -d "/root/overlay/${package_name}/" ]] && rsync -aq /root/overlay/"${package_name}" /root/build/
				# set upstream version
				[[ -n "${package_upstream_version}" ]] && debchange --preserve --newversion "${package_upstream_version}" "Import from upstream"
				# set local version
				# debchange -l~armbian${REVISION}-${builddate}+ "Custom $VENDOR release"
				debchange -l~armbian"${REVISION}"+ "Custom $VENDOR release"
				display_alert "Building package"
				dpkg-buildpackage -b -us -j2
				if [[ \$? -eq 0 ]]; then
					cd /root/build
					# install in chroot if other libraries depend on them
					if [[ -n "$package_install_chroot" ]]; then
						display_alert "Installing packages"
						for p in $package_install_chroot; do
							dpkg -i \${p}_*.deb
						done
					fi
					display_alert "Done building" "$package_name $release/$arch" "ext"
					ls *.deb 2>/dev/null
					mv *.deb /root 2>/dev/null
					exit 0
				else
					display_alert "Failed building" "$package_name $release/$arch" "err"
					exit 2
				fi
				EOF

				chmod +x "${target_dir}"/root/build.sh

				fetch_from_repo "$package_repo" "extra/$package_name" "$package_ref"

				eval systemd-nspawn -a -q --capability=CAP_MKNOD -D "${target_dir}" --tmpfs=/root/build --tmpfs=/tmp:mode=777 --bind-ro "${SRC}"/packages/extras-buildpkgs/:/root/overlay \
					--bind-ro "${SRC}"/cache/sources/extra/:/root/sources /bin/bash -c "/root/build.sh" 2>&1 \
					${PROGRESS_LOG_TO_FILE:+' | tee -a $DEST/debug/buildpkg.log'}
				if [[ ${PIPESTATUS[0]} -eq 2 ]]; then
					failed+=("$package_name:$release/$arch")
				else
					built_ok+=("$package_name:$release/$arch")
				fi
				mv "${target_dir}"/root/*.deb "${plugin_target_dir}" 2>/dev/null
			done
			# cleanup for distcc
			kill "$(<"/var/run/distcc/${release}-${arch}.pid")"
		done
	done
	if [[ ${#built_ok[@]} -gt 0 ]]; then
		display_alert "Following packages were built without errors" "" "info"
		for p in ${built_ok[@]}; do
			display_alert "$p"
		done
	fi
	if [[ ${#failed[@]} -gt 0 ]]; then
		display_alert "Following packages failed to build" "" "wrn"
		for p in ${failed[@]}; do
			display_alert "$p"
		done
	fi
} #############################################################################

# chroot_installpackages_local
#
chroot_installpackages_local()
{
	local conf="${SRC}"/config/aptly-temp.conf
	rm -rf /tmp/aptly-temp/
	mkdir -p /tmp/aptly-temp/
	aptly -config="${conf}" repo create temp >> "${DEST}"/debug/install.log
	# NOTE: this works recursively
	aptly -config="${conf}" repo add temp "${DEB_STORAGE}/extra/${RELEASE}-desktop/" >> "${DEST}"/debug/install.log
	aptly -config="${conf}" repo add temp "${DEB_STORAGE}/extra/${RELEASE}-utils/" >> "${DEST}"/debug/install.log
	# -gpg-key="925644A6"
	aptly -keyring="${SRC}/packages/extras-buildpkgs/buildpkg-public.gpg" -secret-keyring="${SRC}/packages/extras-buildpkgs/buildpkg.gpg" -batch=true -config="${conf}" \
		 -gpg-key="925644A6" -passphrase="testkey1234" -component=temp -distribution="${RELEASE}" publish repo temp >> "${DEST}"/debug/install.log
	aptly -config="${conf}" -listen=":8189" serve &
	local aptly_pid=$!
	cp "${SRC}"/packages/extras-buildpkgs/buildpkg.key "${SDCARD}"/tmp/buildpkg.key
	cat <<-'EOF' > "${SDCARD}"/etc/apt/preferences.d/90-armbian-temp.pref
	Package: *
	Pin: origin "localhost"
	Pin-Priority: 550
	EOF
	cat <<-EOF > "${SDCARD}"/etc/apt/sources.list.d/armbian-temp.list
	deb http://localhost:8189/ $RELEASE temp
	EOF
	chroot_installpackages
	kill "${aptly_pid}"
} #############################################################################

# chroot_installpackages <remote_only>
#
chroot_installpackages()
{
	local remote_only=$1
	local install_list=""
	for plugin in "${SRC}"/packages/extras-buildpkgs/*.conf; do
		source "${plugin}"
		if [[ $(type -t package_checkinstall) == function ]] && package_checkinstall; then
			install_list="$install_list $package_install_target"
		fi
		unset package_install_target package_checkinstall
	done
	if [[ -n $PACKAGE_LIST_RM ]]; then
        install_list=$(sed -r "s/\W($(tr ' ' '|' <<< ${PACKAGE_LIST_RM}))\W/ /g" <<< " ${install_list} ")
        install_list="$(echo ${install_list})"
	fi
	display_alert "Installing extras-buildpkgs" "$install_list"

	[[ $NO_APT_CACHER != yes ]] && local apt_extra="-o Acquire::http::Proxy=\"http://${APT_PROXY_ADDR:-localhost:3142}\" -o Acquire::http::Proxy::localhost=\"DIRECT\""
	cat <<-EOF > "${SDCARD}"/tmp/install.sh
	#!/bin/bash
	[[ "$remote_only" != yes ]] && apt-key add /tmp/buildpkg.key
	apt-get ${apt_extra} -q update
	# uncomment to debug
	# /bin/bash
	# TODO: check if package exists in case new config was added
	#if [[ -n "$remote_only" == yes ]]; then
	#	for p in ${install_list}; do
	#		if grep -qE "apt.armbian.com|localhost" <(apt-cache madison \$p); then
	#		if apt-get -s -qq install \$p; then
	#fi
	apt-get -q ${apt_extra} --show-progress -o DPKG::Progress-Fancy=1 install -y ${install_list}
	apt-get clean
	[[ "${remote_only}" != yes ]] && apt-key del "925644A6"
	rm /etc/apt/sources.list.d/armbian-temp.list 2>/dev/null
	rm /etc/apt/preferences.d/90-armbian-temp.pref 2>/dev/null
	rm /tmp/buildpkg.key 2>/dev/null
	rm -- "\$0"
	EOF
	chmod +x "${SDCARD}"/tmp/install.sh
	chroot "${SDCARD}" /bin/bash -c "/tmp/install.sh" >> "${DEST}"/debug/install.log 2>&1
} #############################################################################
