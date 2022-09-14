#! /bin/bash

[ "$__time_traced" ] ||
    __time_traced=yes exec time "$0" "$@"

#	Exit on errors.

ARCH=$1

set -xe

#	Travis stuff.

XORRISO_PKGS='
	libburn4
	libisoburn1
	libisofs6
	libjte2
	mtools
	sshpass
	xorriso
'

GRUB_EFI_PKGS='
	grub-efi-amd64
	grub-efi-amd64-signed
	shim-signed
'

apt -qq update
apt -yy install $XORRISO_PKGS $GRUB_EFI_PKGS --no-install-recommends >/dev/null

#	base image URL.

GIT_COMMIT=$(git rev-parse --short HEAD)
GIT_CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
OS_VERSION="0.1.0-alpha"
BASE_IMAGE_VERSION="0.1.0-alpha"

BASE_IMG_URL="https://github.com/kaytime/base/releases/download/$BASE_IMAGE_VERSION/rootfs-$GIT_CURRENT_BRANCH-latest-$ARCH.tar.xz"

#	Prepare the directories for the build.

mkdir system_build
mkdir system_iso
mkdir system_ouput

build_dir=$PWD/system_build
iso_dir=$PWD/system_iso
output_dir=$PWD/system_ouput

chmod 755 $build_dir

config_dir=$PWD/builder/configs

#	The name of the ISO image.

system_image="kaytime-core-$OS_VERSION-$ARCH.iso"
root_fs="kaytime-core-rootfs-$OS_VERSION-$ARCH.tar"
hash_url="http://updates.os.kaytime.com/${system_image%.iso}.md5sum"

#	Prepare the directory where the filesystem will be created.

wget -qO base.tar.xz $BASE_IMG_URL
tar xf base.tar.xz -C $build_dir

# Install build tools

printf "Installing build tools... "

git clone --branch $GIT_CURRENT_BRANCH https://github.com/kaytime/system-builder-kit builder

cp $PWD/builder/tools/runch /bin/runch
cp $PWD/builder/tools/mkiso /bin/mkiso
chmod +x /bin/runch
chmod +x /bin/mkiso

#	Populate $build_dir.

printf "Creating filesystem..."

runch <core.sh $GIT_CURRENT_BRANCH \
    -m builder/configs:/configs \
    -r /configs \
    -m layouts:/layouts \
    -r /layouts \
    $build_dir \
    bash || :

#	Check filesystem size.

du -hs $build_dir

#	Remove CI leftovers.

rm -r $iso_dir/home/{travis,Travis} || true

#	Create RootFS File.

cd "$build_dir"

tar -cpf ../"$root_fs" *
cd ..
echo "Done!"

echo "Compressing $root_fs with XZ (using $(nproc) threads)..."
xz -v --threads=$(nproc) "$root_fs"

echo "Successfully created $root_fs.xz."

#	Copy the kernel and initramfs to $iso_dir.
#	BUG: vmlinuz and initrd are not moved to $iso_dir/; they're left at $build_dir/boot

mkdir -p $iso_dir/boot

cp $(echo $build_dir/boot/vmlinuz* | tr " " "\n" | sort | tail -n 1) $iso_dir/boot/kernel
cp $(echo $build_dir/boot/initrd* | tr " " "\n" | sort | tail -n 1) $iso_dir/boot/initramfs

#	WARNING FIXME BUG: This file isn't copied during the chroot.

mkdir -p $iso_dir/boot/grub/x86_64-efi
cp /usr/lib/grub/x86_64-efi/linuxefi.mod $iso_dir/boot/grub/x86_64-efi

#	Copy EFI folder to ISO

cp -r EFI/ $iso_dir/

#	Copy ucode to ISO

cp -r ucode/ $iso_dir/boot/

#	Compress the root filesystem.

(while :; do
    sleep 300
    printf ".\n"
done) &

mkdir -p $iso_dir/casper
mksquashfs $build_dir $iso_dir/casper/filesystem.squashfs -comp zstd -Xcompression-level 22 -no-progress -b 1048576

#	Generate the ISO image.

git clone https://github.com/kaytime/system-grub-theme system-grub-theme

mkiso \
    -V "KAYTIME" \
    -b \
    -e \
    -s "$hash_url" \
    -r "$(printf "$OS_VERSION")" \
    -g $config_dir/files/grub.cfg \
    -g $config_dir/files/loopback.cfg \
    -t system-grub-theme/kaytime \
    $iso_dir $output_dir/$system_image

#	Calculate the checksum.

md5sum $output_dir/$system_image >$output_dir/${image%.iso}.md5sum

echo "Done!"
