#! /bin/bash

install_drivers_layout() {
    add_repo_keys \
        541922FB \
        61FC752C >/dev/null

    cp /builder/configs/files/sources.list.devuan.daedalus /etc/apt/sources.list.d/devuan-daedalus-repo.list

    update

    KAYTIME_DRIVERS_PKGS='
        system-layer-graphical
    '

    install $KAYTIME_DRIVERS_PKGS

    rm \
        /etc/apt/sources.list.d/devuan-daedalus-repo.list

    remove_repo_keys \
        541922FB \
        61FC752C >/dev/null

    update
}
