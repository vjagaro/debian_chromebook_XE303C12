#!/bin/bash

set -e

source /etc/os-release

figlet "Release: $VERSION_CODENAME"
figlet "CPUs: $(nproc)"

mkdir -p build
cd build

if [ "$VERSION_CODENAME" == "bullseye" ]; then
	tar xJf /usr/src/linux-source-5.10.tar.xz
	cd linux-source-5.10
elif [ "$VERSION_CODENAME" == "bookworm" ]; then
	tar xJf /usr/src/linux-source-6.1.tar.xz
	cd linux-source-6.1
elif [ "$VERSION_CODENAME" == "trixie" ]; then
	tar xJf /usr/src/linux-source-6.12.tar.xz
	cd linux-source-6.12
else
	echo "Unsupported"
	exit 1
fi

kernel_version="$(make kernelversion)"

export kernel_version
figlet "KERNEL: $kernel_version"
# shellcheck disable=SC2206
vers=(${kernel_version//./ })
version="${vers[0]}.${vers[1]}"
figlet "VERSION: $version"

# Get TI firmwares
mkdir -p firmware
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-bone-scale-data.bin?h=ti-v4.1.y -O firmware/am335x-bone-scale-data.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-evm-scale-data.bin?h=ti-v4.1.y -O firmware/am335x-evm-scale-data.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-pm-firmware.bin?h=ti-v4.1.y -O firmware/am335x-pm-firmware.bin
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am335x-pm-firmware.elf?h=ti-v4.1.y -O firmware/am335x-pm-firmware.elf
wget https://git.ti.com/cgit/processor-firmware/ti-amx3-cm3-pm-firmware/plain/bin/am43x-evm-scale-data.bin?h=ti-v4.1.y -O firmware/am43x-evm-scale-data.bin

# Copy config, apply and build kernel
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
cp ../../configs/"$version" ./.config
make olddefconfig
make bindeb-pkg "-j$(nproc)"
make dtbs
kver=$(make kernelrelease)
export kver
figlet "KVER: $kver"
if [ "$VERSION_CODENAME" == "trixie" ]; then
	cp ./arch/arm/boot/dts/samsung/exynos5250*.dtb ..
else
	cp ./arch/arm/boot/dts/exynos5250*.dtb ..
fi
