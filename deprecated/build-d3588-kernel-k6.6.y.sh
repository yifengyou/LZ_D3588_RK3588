#!/bin/bash

set -uxo pipefail

WORKDIR=$(pwd)
export DEBIAN_FRONTEND=noninteractive

#==========================================================================#
#                        init build env                                    #
#==========================================================================#
apt-get update
apt-get install -qq -y ca-certificates
apt-get install -qq -y --no-install-recommends \
  acl aptly aria2 axel bc binfmt-support binutils-aarch64-linux-gnu bison \
  bsdextrautils btrfs-progs build-essential busybox ca-certificates ccache \
  clang coreutils cpio crossbuild-essential-arm64 cryptsetup curl \
  debian-archive-keyring debian-keyring debootstrap device-tree-compiler \
  dialog dirmngr distcc dosfstools dwarves e2fsprogs expect f2fs-tools \
  fakeroot fdisk file flex gawk gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi \
  gdisk git gnupg gzip htop imagemagick jq kmod lib32ncurses-dev \
  lib32stdc++6 libbison-dev libc6-dev-armhf-cross libc6-i386 libcrypto++-dev \
  libelf-dev libfdt-dev libfile-fcntllock-perl libfl-dev libfuse-dev \
  libgcc-12-dev-arm64-cross libgmp3-dev liblz4-tool libmpc-dev libncurses-dev \
  libncurses5 libncurses5-dev libncursesw5-dev libpython2.7-dev \
  libpython3-dev libssl-dev libusb-1.0-0-dev linux-base lld llvm locales \
  lsb-release lz4 lzma lzop make mtools ncurses-base ncurses-term \
  nfs-kernel-server ntpdate openssl p7zip p7zip-full parallel parted patch \
  patchutils pbzip2 pigz pixz pkg-config pv python2 python2-dev python3 \
  python3-dev python3-distutils python3-pip python3-setuptools \
  python-is-python3 qemu-user-static rar rdfind rename rsync sed \
  squashfs-tools swig tar tree u-boot-tools udev unzip util-linux uuid \
  uuid-dev uuid-runtime vim wget whiptail xfsprogs xsltproc xxd xz-utils \
  zip zlib1g-dev zstd binwalk ripgrep sudo
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true
mkdir -p ${WORKDIR}/rockdev
mkdir -p ${WORKDIR}/release

#==========================================================================#
#                        build uboot                                       #
#==========================================================================#
cd ${WORKDIR}/
# https://github.com/yifengyou/d3588-uboot.git fork from radxa/u-boot.git
# git clone -b stable-5.10-rock5 https://github.com/yifengyou/d3588-uboot.git u-boot.git
git clone -b stable-5.10-rock5 https://github.com/radxa/u-boot.git u-boot.git
cd u-boot.git
ls -alh

# apply patch
if ls "${WORKDIR}/radxa-uboot/"*.patch >/dev/null 2>&1; then
  git config --global user.name yifengyou
  git config --global user.email 842056007@qq.com
  git am ${WORKDIR}/radxa-uboot/*.patch
fi

# build uboot.img
chmod +x ${WORKDIR}/radxa-uboot/d3588.sh
cp -a ${WORKDIR}/radxa-uboot/d3588.sh .
cat d3588.sh
./d3588.sh

mv uboot.img ${WORKDIR}/release/uboot.img
ls -alh ${WORKDIR}/release/uboot.img
md5sum ${WORKDIR}/release/uboot.img

#==========================================================================#
#                        build kernel                                      #
#==========================================================================#
cd ${WORKDIR}
git clone https://github.com/ophub/linux-6.6.y.git linux-6.6.y.git
cd linux-6.6.y.git
ls -alh

# apply patch
if ls "${WORKDIR}/kernel-6.6.y/"*.patch >/dev/null 2>&1; then
  git config --global user.name yifengyou
  git config --global user.email 842056007@qq.com
  git am ${WORKDIR}/kernel-6.6.y/*.patch
fi

if [ -d ${WORKDIR}/kernel-6.6.y ]; then
  ls -alh ${WORKDIR}/kernel-6.6.y/
  cp -a ${WORKDIR}/kernel-6.6.y/* .
  ls -alh
fi

# build kernel Image
if [ -f build.sh ]; then
  chmod +x build.sh
  ./build.sh
else
  echo "no build.sh found!"
  exit 1
fi

# release kernel image
ls -alh arch/arm64/boot/Image
md5sum arch/arm64/boot/Image
cp -a arch/arm64/boot/Image ${WORKDIR}/release/

# release dtb
ls -alh ./arch/arm64/boot/dts/rockchip/rk3588-liontron-d3588.dtb
md5sum ./arch/arm64/boot/dts/rockchip/rk3588-liontron-d3588.dtb
cp -a ./arch/arm64/boot/dts/rockchip/rk3588-liontron-d3588.dtb ${WORKDIR}/release/

# release config
cp .config ${WORKDIR}/release/config-6.6.y-kdev
ls -alh ${WORKDIR}/release/config-6.6.y-kdev
md5sum ${WORKDIR}/release/config-6.6.y-kdev

# release system map
cp System.map ${WORKDIR}/release/System.map-6.6.y-kdev
ls -alh ${WORKDIR}/release/System.map-6.6.y-kdev
md5sum ${WORKDIR}/release/System.map-6.6.y-kdev

# release kernel modules
if [ -d kos/lib/modules ]; then
  find kos -name "*.ko"
  ls -alh kos/lib/modules/
  tar -zcvf ${WORKDIR}/release/kos.tar.gz kos
fi

ls -alh ${WORKDIR}/release/
echo "Build completed successfully!"
exit 0
