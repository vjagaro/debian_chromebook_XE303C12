#!/usr/bin/env bash

set -euo pipefail

[ "$(id -u)" -eq 0 ] && exit 1

CHROMEBOOK_HOSTNAME=chromebook

cd build

sudo rm -rf rootfs
sudo debootstrap --arch=armhf trixie rootfs http://deb.debian.org/debian/

sudo tee rootfs/etc/apt/sources.list.d/debian.sources >/dev/null <<EOF
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

sudo rm -f rootfs/etc/apt/sources.list

sudo tee rootfs/etc/hosts >/dev/null <<EOF
# /etc/hosts
127.0.0.1       localhost $CHROMEBOOK_HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1             localhost $CHROMEBOOK_HOSTNAME ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF

echo "$CHROMEBOOK_HOSTNAME" | sudo tee rootfs/etc/hostname >/dev/null

sudo tee rootfs/etc/network/interfaces.d/lo >/dev/null <<EOF
auto lo
iface lo inet loopback
EOF

sudo tee rootfs/etc/resolv.conf >/dev/null <<EOF
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

sudo mkdir -p rootfs/chromebook

sudo cp -f linux-*.deb rootfs/chromebook

sudo tee rootfs/chromebook/setup.sh >/dev/null <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

export LANG=C
export LC_ALL=C

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates \
  e2fsprogs \
  firmware-libertas \
  firmware-linux-free \
  firmware-linux-nonfree \
  firmware-qcom-soc \
  firmware-realtek \
  firmware-samsung \
  initramfs-tools \
  laptop-mode-tools \
  locales \
  locales-all \
  network-manager \
  parted \
  sudo \
  util-linux \
  wget \
  wpasupplicant

# Install downgraded cgpt
# https://github.com/hexdump0815/imagebuilder/blob/main/doc/important-information.md#23-09-25-cgpt-seems-to-be-broken-on-32bit-armv7l-systems-in-debian-bookworm
(
  cd /tmp
  wget https://ftp.debian.org/debian/pool/main/v/vboot-utils/cgpt_0~R88-13597.B-1_armhf.deb
  dpkg -i cgpt_0~R88-13597.B-1_armhf.deb
  rm -f cgpt_0~R88-13597.B-1_armhf.deb
)

DEBIAN_FRONTEND=noninteractive apt-get install -y /chromebook/linux-*.deb
apt-get clean
rm -f /var/lib/apt/lists/* || true

echo "root:toor" | chpasswd
EOF

sudo mount -t proc proc rootfs/proc
sudo mount -o bind /dev rootfs/dev
sudo mount -o bind /dev/pts rootfs/dev/pts
sudo chroot rootfs /usr/bin/bash /chromebook/setup.sh
sudo umount rootfs/dev/pts
sudo umount rootfs/dev
sudo umount rootfs/proc

sudo rm -rf rootfs/chromebook

mkdir -p kernel
cp -f rootfs/boot/vmlinuz* kernel/zImage
mkdir -p kernel/dts
cp -f linux-source-6.12/arch/arm/boot/dts/samsung/exynos5250*.dtb kernel/dts
dd if=/dev/zero of=kernel/bootloader bs=512 count=1
echo 'noinitrd console=tty0 root=PARTUUID=%U/PARTNROFF=2 rootwait rw rootfstype=ext4' >kernel/kernel-usb.config
echo 'noinitrd console=tty0 root=/dev/mmcblk0p3 rootwait rw rootfstype=ext4' >kernel/kernel-emmc.config

cat >kernel/kernel-exynos.its <<EOF
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

( cd kernel && mkimage -D "-I dts -O dtb -p 2048" -f kernel-exynos.its kernel-exynos )

mkdir -p xe303c12

vbutil_kernel \
  --arch arm \
  --pack xe303c12/kernel_usb.bin \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --version 1 \
  --config kernel/kernel-usb.config \
  --bootloader kernel/bootloader \
  --vmlinuz kernel/kernel-exynos

vbutil_kernel \
  --arch arm \
  --pack xe303c12/kernel_emmc_ext4.bin \
  --keyblock /usr/share/vboot/devkeys/kernel.keyblock \
  --signprivate /usr/share/vboot/devkeys/kernel_data_key.vbprivk \
  --version 1 \
  --config kernel/kernel-emmc.config \
  --bootloader kernel/bootloader \
  --vmlinuz kernel/kernel-exynos

rm -f xe303c12/rootfs.tar.xz
( cd rootfs && sudo tar pcJf ../xe303c12/rootfs.tar.xz ./* )
sudo chown $(id -u):$(id -g) xe303c12/rootfs.tar.xz
cp ../scripts/install.sh xe303c12
touch xe303c12/xfce_install.sh

mkdir -p ../release
zip -r ../release/xe303c12.zip xe303c12

# TODO: should these be installed?
#  abootimg fake-hwclock u-boot-tools device-tree-compiler vboot-utils vboot-kernel-utils
#  xz-utils u-boot-tools console-common less git alsa-utils pulseaudio
