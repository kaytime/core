#! /bin/bash

set -xe

export LANG=C
export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive

puts() { printf "\n\n --- %s\n" "$*"; }

BUILD_CHANNEL=$1

#	Wrap APT commands in functions.

source /configs/scripts/apt_funcs.sh

#	Wrap Debian build commands in functions.

source /configs/scripts/builder/main.sh

#	Wrap Layout build commands in functions.

source /layouts/main.sh

puts "STARTING BOOTSTRAP."

#	Block installation of some packages.

cp /configs/files/preferences /etc/apt/preferences

#	Install basic packages.

puts "ADDING BASIC PACKAGES."

install_basic_packages

#	Add key for Kaytime repository.

puts "ADDING REPOSITORY KEYS."

add_kaytime_key_repo
add_kaytime_key_compat
add_kaytime_key_testing

#	Copy repository sources.

puts "ADDING SOURCES FILES."

adding_sources_file

#	Upgrade dpkg for zstd support.

UPGRADE_DPKG='
	dpkg=1.21.1ubuntu1
'

install_downgrades $UPGRADE_DPKG

#	Do dist-upgrade.

dist_upgrade

#	Add bootloader.
#
#	The GRUB2 packages from Debian do not work correctly with EFI.

puts "ADDING BOOTLOADER."

adding_bootloader

#	Add packages for secure boot compatibility.

puts "ADDING SECURE BOOT COMPAT."

adding_secure_boot

#	Add eudev, elogind, and systemctl to replace systemd and utilize other inits.
#
#	To remove systemd, we have to replace libsystemd0, udev, elogind and provide systemctl. However, neither of them
#	are available to install from other sources than Devuan except for systemctl.

add_repo_keys \
	541922FB \
	61FC752C >/dev/null

cp /configs/files/sources.list.devuan.beowulf /etc/apt/sources.list.d/devuan-beowulf-repo.list

update

puts "ADDING EUDEV AND ELOGIND."

adding_devuan_and_elogind

#	Add OpenRC as init.

puts "ADDING OPENRC AS INIT."

adding_open_rc

#	Add casper.
#
#	It's worth noting that casper isn't available anywhere but Ubuntu.
#	Debian doesn't use it; it uses live-boot, live-config, et. al.

puts "ADDING CASPER."

adding_casper

#	Add kernel.

puts "ADDING KERNEL."

adding_system_firmware

#	Add Plymouth.
#
#	The version of Plymouth that is available from Debian requires systemd and udev.
#	To avoid this requirement, we will use the package from Devuan (daedalus) that only requires udev (eudev).

puts "ADDING PLYMOUTH."

adding_plymouth

#	Adding PolicyKit packages from Devuan.
#
#	Since we're using elogind to replace logind, we need to add the matching PolicyKit packages.
#
#	Strangely, the complete stack is only available in beowulf but not in chimaera or daedalus.

puts "ADDING POLICYKIT ELOGIND COMPAT."

adding_policykit_elogind

#	Add misc. Devuan packages.
#
#	The network-manager package that is available in Debian does not have an init script compatible with OpenRC.
#	so we use the package from Devuan instead.
#
#	Prioritize installing packages from daedalus over chimaera, unless the package only exists in ceres.

puts "ADDING DEVUAN MISC. PACKAGES."

adding_devuan_misc_packages

#	Add Kaytime Drivers meta-packages.
#
#	31/05/22 - Once again the package 'broadcom-sta-dkms' is broken with the latest kernel 5.18.

puts "ADDING KAYTIME BASE."

install_core_layout

puts "ADDING KAYTIME DRIVERS."

install_drivers_layout

#	Add Nvidia drivers or Nouveau.
#
#	The package nouveau-firmware isn't available in Debian but only in Ubuntu.
#
#	The Nvidia proprietary driver can't be installed alongside Nouveau.
#
#	To install it replace the Nouveau packages with the Nvidia counterparts.

puts "ADDING NVIDIA DRIVERS/NOUVEAU FIRMWARE."

NVIDIA_DRV_PKGS='
	xserver-xorg-video-nouveau
	nouveau-firmware
'

install $NVIDIA_DRV_PKGS

#	Upgrade MESA packages.

puts "UPDATING MESA."

MESA_GIT_PKGS='
	mesa-git
'

MESA_LIBS_PKGS='
	libdrm-amdgpu1
	libdrm-common
	libdrm-intel1
	libdrm-nouveau2
	libdrm-radeon1
	libdrm2
	libegl-mesa0
	libgbm1
	libgl1-mesa-dri
	libglapi-mesa
	libglx-mesa0
	libxatracker2
	mesa-va-drivers
	mesa-vdpau-drivers
	mesa-vulkan-drivers
'

install $MESA_GIT_PKGS
only_upgrade_force_overwrite $MESA_LIBS_PKGS

#	Add OpenRC configuration.
#
#	Due to how the upstream openrc package "works," we need to put this package at the end of the build process.
#	Otherwise, we end up with an unbootable system.
#
#	See https://github.com/kaytime/system-openrc-config/issues/1

puts "ADDING OPENRC CONFIG."

OPENRC_CONFIG='
	openrc-config
'

install $OPENRC_CONFIG

#	Remove sources used to build the root.

puts "REMOVE BUILD SOURCES."

rm \
	/etc/apt/preferences \
	/etc/apt/sources.list.d/* \
	/usr/share/keyrings/kaytime-repo.gpg \
	/usr/share/keyrings/kaytime-compat.gpg

update

#	Update Appstream cache.

clean_all
update
appstream_refresh_force

#	Add repository configuration.

puts "ADDING REPOSITORY SETTINGS."

KAYTIME_REPO_PKG='
	system-repositories-config
'

install $KAYTIME_REPO_PKG

#	Unhold initramfs and casper packages.

unhold $INITRAMFS_CASPER_PKGS

#	WARNING:
#	No apt usage past this point.

#	Changes specific to this image. If they can be put in a package, do so.
#	FIXME: These fixes should be included in a package.

puts "ADDING MISC. FIXES."

rm \
	/etc/default/grub \
	/etc/casper.conf

cat /configs/files/grub >/etc/default/grub
cat /configs/files/casper.conf >/etc/casper.conf

rm \
	/boot/{vmlinuz,initrd.img,vmlinuz.old,initrd.img.old} || true

cat /configs/files/motd >/etc/motd

printf '%s\n' fuse nouveau amdgpu >>/etc/modules

cat /configs/files/adduser.conf >/etc/adduser.conf

#	Generate initramfs.

puts "UPDATING THE INITRAMFS."

update-initramfs -c -k all

#	Before removing dpkg, check the most oversized installed packages.

puts "SHOW LARGEST INSTALLED PACKAGES.."

list_pkgs_size
list_number_pkgs
list_installed_pkgs

#	WARNING:
#	No dpkg usage past this point.

puts "PERFORM MANUAL CHECKS."

ls -lh \
	/boot \
	/etc/runlevels/{boot,default,nonetwork,off,recovery,shutdown,sysinit} \
	/{vmlinuz,initrd.img} \
	/etc/{init.d,sddm.conf.d} \
	/usr/lib/dbus-1.0/dbus-daemon-launch-helper \
	/Applications || true

stat /sbin/init \
	/bin/sh \
	/bin/dash \
	/bin/bash

cat \
	/etc/{casper.conf,sddm.conf,modules} \
	/etc/default/grub \
	/etc/environment \
	/etc/adduser.conf

puts "EXITING BOOTSTRAP."
