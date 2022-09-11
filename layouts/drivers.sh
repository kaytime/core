#! /bin/bash

install_drivers_layout() {
    KAYTIME_DRIVERS_PKGS='
        system-layer-drivers
    '

    install $KAYTIME_DRIVERS_PKGS
}
