#! /bin/bash

install_firmware_layout() {
    MAINLINE_KERNEL_PKG='
	linux-image-xanmod-edge
	libcrypt-dev/trixie
	libcrypt1/trixie
'

    install_downgrades $MAINLINE_KERNEL_PKG

    rm \
        /etc/apt/sources.list.d/xanmod-repo.list

    remove_repo_keys \
        86F7D09EE734E623 >/dev/null

    update
}
