#!/usr/bin/env bash

set -euo pipefail

[ "$(id -u)" -eq 0 ] || exit 1

CHROMEBOOK_HOSTNAME=chromebook
VERSION_CODENAME=trixie
#source /etc/os-release

cd build
debootstrap --arch=armhf "$VERSION_CODENAME" root http://deb.debian.org/debian/

cat <<EOF >root/etc/apt/sources.list.d/debian.sources
Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://deb.debian.org/debian/
Suites: trixie-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb deb-src
URIs: http://deb.debian.org/debian-security/
Suites: trixie-security/updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

rm -f root/etc/apt/sources.list

echo "$CHROMEBOOK_HOSTNAME" >root/etc/hostname

cat <<EOF >root/etc/hosts
# /etc/hosts
127.0.0.1       localhost $CHROMEBOOK_HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1             localhost $CHROMEBOOK_HOSTNAME ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

cat <<EOF >root/etc/network/interfaces.d/lo
auto lo
iface lo inet loopback
EOF

cat <<EOF >root/etc/resolv.conf
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

mkdir -p root/boot/kernel root/boot/dts
cp -f linux-*.deb root/boot/kernel
cp -f exynos*.dtb root/boot/dts

cat <<EOF >root/boot/kernel-exynos.its
/dts-v1/;

/ {
    description = "Chrome OS kernel image with one or more FDT blobs";
    images {
        kernel@1{
            description = "kernel";
            data = /incbin/("zImage");
            type = "kernel_noload";
            arch = "arm";
            os = "linux";
            compression = "none";
            load = <0>;
            entry = <0>;
          };
        fdt@1 {
            description = "exynos5250-snow.dtb";
            data = /incbin/("dts/exynos5250-snow.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1 {
                algo = "sha1";
            };
        };
        fdt@2 {
            description = "exynos5250-snow-rev5.dtb";
            data = /incbin/("dts/exynos5250-snow-rev5.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1 {
                algo = "sha1";
            };
        };
        fdt@3 {
            description = "exynos5250-spring.dtb";
            data = /incbin/("dts/exynos5250-spring.dtb");
            type = "flat_dt";
            arch = "arm";
            compression = "none";
            hash@1 {
                algo = "sha1";
            };
        };
      };
    configurations {
        default = "conf@1";
        conf@1{
            kernel = "kernel@1";
            fdt = "fdt@1";
          };
        conf@2{
            kernel = "kernel@1";
            fdt = "fdt@2";
          };
        conf@3 {
            kernel = "kernel@1";
            fdt = "fdt@3";
          };
      };
  };
EOF

apt-get install -y schroot

cat <<EOF >/etc/schroot/chroot.d/xe303c12.conf
[xe303c12]
directory=$(pwd)/root
root-users=root
users=root
type=directory
EOF

cat <<EOF | schroot -c xe303c12 bash

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	abootimg cgpt fake-hwclock u-boot-tools device-tree-compiler vboot-utils vboot-kernel-utils \
	initramfs-tools parted sudo xz-utils wpasupplicant  \
	locales-all ca-certificates initramfs-tools u-boot-tools locales \
	console-common less network-manager git laptop-mode-tools \
	alsa-utils pulseaudio python3 wget zstd \
	firmware-linux-nonfree firmware-linux-free firmware-misc-nonfree firmware-qcom-soc firmware-realtek firmware-libertas firmware-samsung

# Downgrade cgpt (workaround bug
# https://github.com/hexdump0815/imagebuilder/blob/main/doc/important-information.md#23-09-25-cgpt-seems-to-be-broken-on-32bit-armv7l-systems-in-debian-bookworm
(
  cd /tmp
  wget https://ftp.debian.org/debian/pool/main/v/vboot-utils/cgpt_0~R88-13597.B-1_armhf.deb
  dpkg -i cgpt_0~R88-13597.B-1_armhf.deb
  rm -f cgpt_0~R88-13597.B-1_armhf.deb
)

DEBIAN_FRONTEND=noninteractive apt-get install -y /boot/kernel/linux-*.deb

cd /boot
cp vmlinuz* zImage
mkimage -D "-I dts -O dtb -p 2048" -f kernel-exynos.its exynos-kernel
dd if=/dev/zero of=bootloader.bin bs=512 count=1
echo 'noinitrd console=tty0 root=PARTUUID=%U/PARTNROFF=2 rootwait rw rootfstype=ext4' >cmdline
vbutil_kernel --arch arm --pack /kernel_usb.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline \
	--bootloader bootloader.bin --vmlinuz exynos-kernel
echo 'noinitrd console=tty0 root=/dev/mmcblk0p3 rootwait rw rootfstype=ext4' >cmdline
vbutil_kernel --arch arm --pack /kernel_emmc_ext4.bin --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
	--signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk --version 1 --config cmdline \
	--bootloader bootloader.bin --vmlinuz exynos-kernel
rm -f zImage cmdline exynos-kernel bootloader.bin

echo "root:toor" | chpasswd

EOF

mkdir -p xe303c12
mv root/kernel_*.bin xe303c12
( cd root && tar pcJf ../xe303c12/rootfs.tar.xz ./* )
cp ../scripts/install.sh xe303c12
touch xe303c12/xfce_install.sh
mkdir -p ../release
zip -r ../release/xe303c12.zip xe303c12/
