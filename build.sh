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

base_img_url=http://cdimage.ubuntu.com/ubuntu-base/releases/20.04/release/ubuntu-base-20.04.3-base-amd64.tar.gz

#	Prepare the directories for the build.

build_dir=$(mktemp -d)
iso_dir=$(mktemp -d)
output_dir=$(mktemp -d)

chmod 755 $build_dir

config_dir=$PWD/builder/configs

#	The name of the ISO image.

git_commit=$(git rev-parse --short HEAD)
image=kaytime-core-$(printf "$GITHUB_BRANCH\n")-$(printf "$git_commit")-amd64.iso
# image=nitrux-$(printf "$TRAVIS_BRANCH\n" | sed "s/legacy/nx-desktop/")-$(date +%Y%m%d)-amd64.iso
hash_url=http://updates.os.kaytime.com/${image%.iso}.md5sum

#	Prepare the directory where the filesystem will be created.

wget -qO base.tar.xz $base_img_url
tar xf base.tar.xz -C $build_dir

# Install build tools

git clone https://github.com/kaytime/system-builder-kit builder

cd $PWD/builder/tools/runch /bin/runch
cd $PWD/builder/tools/mkiso /bin/mkiso
chmod +x /bin/runch
chmod +x /bin/mkiso

#	Populate $build_dir.

runch core.sh $GIT_BRANCH \
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
    -r "$(printf "$git_commit")" \
    -g $config_dir/files/grub.cfg \
    -g $config_dir/files/loopback.cfg \
    -t system-grub-theme/kaytime \
    $iso_dir $output_dir/$image

#	Calculate the checksum.

md5sum $output_dir/$image >$output_dir/${image%.iso}.md5sum

#	Upload the ISO image.

for f in $output_dir/*; do
    SSHPASS=$FOSSHOST_PASSWORD sshpass -e scp -q -o stricthostkeychecking=no "$f" $FOSSHOST_USERNAME@$FOSSHOST_HOST:$FOSSHOST_DEPLOY_PATH
done
