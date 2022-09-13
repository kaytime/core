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

git_commit=$(git rev-parse --short HEAD)
git_current_branch=$(git rev-parse --abbrev-ref HEAD)
base_img_url="stable"

# Switch
while :; do
    case $git_current_branch in
    stable)
        base_img_url=$BASE_IMAGE_STABLE
        break
        ;;
    unstable)
        base_img_url=$BASE_IMAGE_UNSTABLE
        break
        ;;
    testing)
        base_img_url=$BASE_IMAGE_TESTING
        break
        ;;
    *)
        base_img_url=$BASE_IMAGE_STABLE
        break
        ;;
    esac
done

#	Prepare the directories for the build.

mkdir -r system_build
mkdir -r system_iso
mkdir -r system_ouput

build_dir=$PWD/system_build
iso_dir=$PWD/system_iso
output_dir=$PWD/system_ouput

chmod 755 $build_dir

config_dir=$PWD/builder/configs

#	The name of the ISO image.

image=kaytime-core-$(printf "$git_current_branch\n")-$(printf "$git_commit")-amd64.iso
root_fs=kaytime-core-$(printf "$git_current_branch\n")-$(printf "$git_commit")-rootfs.tar
root_fs_latest=kaytime-core-$(printf "$git_current_branch\n")-latest-rootfs.tar
hash_url=http://updates.os.kaytime.com/${image%.iso}.md5sum

#	Prepare the directory where the filesystem will be created.

wget -qO base.tar.xz $base_img_url
tar xf base.tar.xz -C $build_dir

# Install build tools

printf "Installing build tools... "

git clone https://github.com/kaytime/system-builder-kit builder

cp $PWD/builder/tools/runch /bin/runch
cp $PWD/builder/tools/mkiso /bin/mkiso
chmod +x /bin/runch
chmod +x /bin/mkiso

#	Populate $build_dir.

printf "Creating filesystem... "

runch core.sh $git_current_branch \
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

# Moving generated archive

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
    -r "$(printf "$git_commit")" \
    -g $config_dir/files/grub.cfg \
    -g $config_dir/files/loopback.cfg \
    -t system-grub-theme/kaytime \
    $iso_dir $output_dir/$image

#	Calculate the checksum.

md5sum $output_dir/$image >$output_dir/${image%.iso}.md5sum

echo "Done!"
