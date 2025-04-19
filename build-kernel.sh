#!/usr/bin/env bash

set -euo pipefail

[ "$(id -u)" -eq 0 ] && exit 1

sudo dpkg --add-architecture armhf
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get build-dep -y linux-source-6.12
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  build-essential \
  crossbuild-essential-armhf \
  debootstrap \
  git \
  qemu-user \
  qemu-user-binfmt \
  qemu-user-static \
  binfmt-support \
  ca-certificates \
  device-tree-compiler \
  u-boot-tools \
  vboot-kernel-utils \
  cpio \
  gzip \
  rsync \
  xz-utils \
  zip \
  kmod \
  figlet \
  fakeroot \
  dh-exec \
  linux-source-6.12 \
  libssl-dev \
  libssl-dev:armhf \
  ncurses-dev

mkdir -p build
cd build
tar xJf /usr/src/linux-source-6.12.tar.xz
cd linux-source-6.12

cp ../../configs/6.12 ./.config

mkdir -p firmware
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-bone-scale-data.bin?h=ti-v4.1.y -O firmware/am335x-bone-scale-data.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-evm-scale-data.bin?h=ti-v4.1.y -O firmware/am335x-evm-scale-data.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-pm-firmware.bin?h=ti-v4.1.y -O firmware/am335x-pm-firmware.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-pm-firmware.elf?h=ti-v4.1.y -O firmware/am335x-pm-firmware.elf
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am43x-evm-scale-data.bin?h=ti-v4.1.y -O firmware/am43x-evm-scale-data.bin

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
make olddefconfig
make bindeb-pkg "-j$(nproc)"
make dtbs

cp arch/arm/boot/dts/samsung/exynos5250*.dtb ..
