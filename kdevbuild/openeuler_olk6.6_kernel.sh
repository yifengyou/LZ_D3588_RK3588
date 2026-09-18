#!/bin/bash

# ========================================================================
# LZ D3588 (RK3588) Linux Kernel & U-Boot 自动化构建脚本
# 功能：编译 U-Boot、Linux OLK-6.6 内核、模块、头文件及 kernel-devel 包
# ========================================================================

set -euxo pipefail

WORKDIR=$(pwd)
export DEBIAN_FRONTEND=noninteractive

LOG_FILE="${WORKDIR}/build-OLK-6.6.log"
# 将标准输出和错误输出同时重定向到日志文件和终端
exec > >(tee -a "$LOG_FILE") 2>&1


#==========================================================================#
#                        1. 初始化构建环境                                  #
#==========================================================================#
echo ">>> [1/7] 安装构建依赖..."
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

# 生成中文 UTF-8 locale，避免部分工具因缺少 locale 报错
localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || true

# 创建产物输出目录
mkdir -p "${WORKDIR}/rockdev"
mkdir -p "${WORKDIR}/release"

#==========================================================================#
#                        2. 获取预编译 U-Boot                               #
#==========================================================================#
echo ">>> [2/7] 下载并部署 U-Boot..."
cd ${WORKDIR}/

wget -c https://github.com/yifengyou/LZ_D3588_RK3588-uboot/releases/download/lz-d3588-uboot/LZ_D3588_UBOOT.zip
unzip LZ_D3588_UBOOT.zip
mv RKDevTool_Release_v3.37/uboot.img ${WORKDIR}/release/uboot.img

ls -alh ${WORKDIR}/release/uboot.img
md5sum ${WORKDIR}/release/uboot.img


#==========================================================================#
#                        3. 克隆内核源码并应用补丁                          #
#==========================================================================#
echo ">>> [3/7] 克隆内核源码..."
cd "${WORKDIR}"

KERNEL_SRC_DIR="OLK-6.6"
git clone -b OLK-6.6 https://atomgit.com/openeuler/kernel "${KERNEL_SRC_DIR}"
cd "${KERNEL_SRC_DIR}"
ls -alh

# apply patch
if ls "${WORKDIR}/openeuler_olk6.6/"*.patch >/dev/null 2>&1; then
  git config --global user.name yifengyou
  git config --global user.email 842056007@qq.com
  git am ${WORKDIR}/openeuler_olk6.6/*.patch
fi

if [ -d ${WORKDIR}/openeuler_olk6.6 ]; then
  ls -alh ${WORKDIR}/openeuler_olk6.6/
  cp -a ${WORKDIR}/openeuler_olk6.6/* .
  ls -alh
fi

#==========================================================================#
#                        4. 配置并编译内核                                  #
#==========================================================================#
echo ">>> [4/7] 配置内核..."

# 加载 LZ D3588 专用 defconfig
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  lz_d3588_defconfig

# 自动处理新增/删除的配置项，保持 .config 与 Kconfig 同步
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  olddefconfig

cat .config

# 校验内核版本号是否包含自定义后缀 -kdev
KVER=$(make LOCALVERSION=-kdev kernelrelease)
KVER="${KVER/kdev*/kdev}"
if [[ "$KVER" != *kdev ]]; then
  echo "ERROR: KVER does not end with 'kdev', got: ${KVER}"
  exit 1
fi
echo "KVER: ${KVER}"

echo ">>> [5/7] 编译内核镜像、设备树和模块..."

# 编译设备树二进制文件 (DTB)
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  dtbs \
  -j$(nproc)

# 编译内核主镜像 (Image)，抑制未使用函数警告
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  KCFLAGS="-Wno-unused-function" \
  -j$(nproc)

# 编译内核模块
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  KCFLAGS="-Wno-unused-function" \
  modules -j$(nproc)

# 安装模块到临时目录 kos/
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  INSTALL_MOD_PATH="$(pwd)/kos" \
  modules_install

# 安装内核头文件
make ARCH=arm64 \
  CROSS_COMPILE=aarch64-linux-gnu- \
  KBUILD_BUILD_USER="builder" \
  KBUILD_BUILD_HOST="kdevbuilder" \
  LOCALVERSION=-kdev \
  INSTALL_HDR_PATH="$(pwd)/kernel-headers/${KVER}" \
  headers_install

KVER=$(cat include/config/kernel.release)
#==========================================================================#
#                        5. 收集构建产物                                    #
#==========================================================================#
echo ">>> [6/7] 收集构建产物到 release/ ..."

# --- 内核镜像 ---
ls -alh arch/arm64/boot/Image
md5sum arch/arm64/boot/Image
cp -a arch/arm64/boot/Image "${WORKDIR}/release/Image-OLK-6.6-kdev"

# --- 设备树 ---
DTB_PATH="./arch/arm64/boot/dts/rockchip/rk3588-lz-d3588.dtb"
ls -alh "${DTB_PATH}"
md5sum "${DTB_PATH}"
cp -a "${DTB_PATH}" "${WORKDIR}/release/"

# --- 内核配置文件 ---
cp .config "${WORKDIR}/release/config-OLK-6.6-kdev"
ls -alh "${WORKDIR}/release/config-OLK-6.6-kdev"
md5sum "${WORKDIR}/release/config-OLK-6.6-kdev"

# --- System.map ---
cp System.map "${WORKDIR}/release/System.map-OLK-6.6-kdev"
ls -alh "${WORKDIR}/release/System.map-OLK-6.6-kdev"
md5sum "${WORKDIR}/release/System.map-OLK-6.6-kdev"

# --- 内核模块打包（strip 版本 + debug 版本）---
if [ -d kos/lib/modules ]; then
  dir_size=$(du -sb kos/lib/modules | awk '{print $1}')
  if [ "$dir_size" -gt 512 ]; then
    # 保留一份未 strip 的调试副本
    cp -a kos kos-debug
    # 对发布版模块去除调试符号以减小体积
    find kos -name "*.ko" -print0 | xargs -0 -r aarch64-linux-gnu-strip --strip-debug
    find kos -name "*.ko"
    ls -alh kos/lib/modules/
    mkdir -p "${WORKDIR}/release"
    tar -zcvf "${WORKDIR}/release/kos-OLK-6.6.tar.gz" kos
  fi
fi

# --- 内核调试信息归档 ---
if [ -f vmlinux ]; then
  mkdir -p "${WORKDIR}/release"
  DEBUGINFO_FILES=()
  for f in vmlinux vmlinux.unstripped System.map Module.symvers .config kos-debug; do
    [ -f "$f" ] && DEBUGINFO_FILES+=("$f")
  done

  if [ ${#DEBUGINFO_FILES[@]} -gt 0 ]; then
    tar -zcvf "${WORKDIR}/release/kernel-debuginfo-OLK-6.6.tar.gz" "${DEBUGINFO_FILES[@]}"
    echo "Kernel debuginfo archived: ${DEBUGINFO_FILES[*]}"
  else
    echo "No debuginfo files found to archive"
  fi
fi

# --- 内核头文件打包 ---
if [ -d kernel-headers ]; then
  mkdir -p "${WORKDIR}/release"
  tar -zcvf "${WORKDIR}/release/kernel-headers-OLK-6.6.tar.gz" kernel-headers
fi

#==========================================================================#
#                        6. 生成 kernel-devel 包                            #
#  用于在目标设备上编译外部内核模块（如 DKMS 驱动）                         #
#==========================================================================#
echo ">>> [7/7] 生成 kernel-devel 包..."
cd "${WORKDIR}/${KERNEL_SRC_DIR}"

ARCH="arm64"
DEVEL_DIR="${WORKDIR}/kernel-devel/${KVER}"

# 重新交叉编译 fixdep 和 modpost，确保它们是 arm64 二进制
# （这两个工具在外部模块编译时会被调用）
rm -f scripts/basic/fixdep
aarch64-linux-gnu-gcc -Wall \
  -Wmissing-prototypes -Wstrict-prototypes -O2 \
  -I scripts/include \
  -o scripts/basic/fixdep \
  scripts/basic/fixdep.c

rm -f scripts/mod/modpost
aarch64-linux-gnu-gcc -Wall \
  -Wmissing-prototypes -Wstrict-prototypes -O2 \
  -I scripts/include \
  -o scripts/mod/modpost \
  scripts/mod/modpost.c \
  scripts/mod/sumversion.c \
  scripts/mod/file2alias.c \
  scripts/mod/symsearch.c

# 清理旧的 devel 目录并重建结构
rm -rf "${DEVEL_DIR}"
mkdir -p "${DEVEL_DIR}/arch/${ARCH}"
mkdir -p "${DEVEL_DIR}/include"
mkdir -p "${DEVEL_DIR}/scripts"
mkdir -p "${DEVEL_DIR}/tools"

# 复制顶层构建文件
cp -a Makefile "${DEVEL_DIR}/"
cp -a Kbuild "${DEVEL_DIR}/"

for f in Module.symvers System.map .config; do
  [ -f "$f" ] && cp -a "$f" "${DEVEL_DIR}/"
done

# 复制 scripts 目录（含编译好的 fixdep/modpost）
cp -a scripts "${DEVEL_DIR}/"

# 复制架构相关脚本
if [ -d "arch/${ARCH}/scripts" ]; then
  mkdir -p "${DEVEL_DIR}/arch/${ARCH}"
  cp -a "arch/${ARCH}/scripts" "${DEVEL_DIR}/arch/${ARCH}/"
fi

# 复制模块链接脚本
if [ -f "scripts/module.lds" ]; then
  mkdir -p "${DEVEL_DIR}/scripts"
  cp -a scripts/module.lds "${DEVEL_DIR}/scripts/"
fi

# 复制头文件
cp -a include "${DEVEL_DIR}/"
if [ -d "arch/${ARCH}/include" ]; then
  cp -a "arch/${ARCH}/include" "${DEVEL_DIR}/arch/${ARCH}/"
fi

# 复制架构 Makefile
if [ -f "arch/${ARCH}/Makefile" ]; then
  cp -a "arch/${ARCH}/Makefile" "${DEVEL_DIR}/arch/${ARCH}/"
fi

# 复制链接器脚本
for lds in arch/${ARCH}/*.lds; do
  [ -f "$lds" ] && cp -a "$lds" "${DEVEL_DIR}/arch/${ARCH}/"
done

# 复制设备树源文件（供外部模块引用 DTS 头文件）
if [ -d "arch/${ARCH}/boot/dts" ]; then
  mkdir -p "${DEVEL_DIR}/arch/${ARCH}/boot/dts"
  find "arch/${ARCH}/boot/dts" \
    \( -name '*.dts' -o -name '*.dtsi' -o -name '*.h' \
    -o -name 'Makefile' -o -name 'Kconfig' -o -name '*.overlay' \) \
    -type f \
    -exec cp --parents {} "${DEVEL_DIR}/" \;
fi

# ARM64 兼容层：复制 arm/include/asm（部分驱动需要）
if [ "${ARCH}" = "arm64" ] && [ -d "arch/arm/include/asm" ]; then
  mkdir -p "${DEVEL_DIR}/arch/arm/include"
  cp -a arch/arm/include/asm "${DEVEL_DIR}/arch/arm/include/"
fi

# 递归复制所有 Makefile/Kconfig/Kbuild 文件（排除已复制目录和 .git）
find . -type f \( -name "Makefile" -o -name "Makefile.*" \
  -o -name "Kconfig" -o -name "Kconfig.*" \
  -o -name "Kbuild" -o -name "Kbuild.*" \) \
  ! -path './kernel-devel/*' \
  ! -path './.git/*' \
  -exec cp --parents {} "${DEVEL_DIR}/" \;

# 如果启用了 objtool，复制其二进制
if grep -q 'CONFIG_OBJTOOL=y' .config 2>/dev/null; then
  if [ -f tools/objtool/objtool ]; then
    mkdir -p "${DEVEL_DIR}/tools/objtool"
    cp -a tools/objtool/objtool "${DEVEL_DIR}/tools/objtool/"
  fi
fi

# 清理 devel 包中不需要的中间文件和临时文件
find "${DEVEL_DIR}" -name ".*.cmd" -delete 2>/dev/null || true
find "${DEVEL_DIR}/scripts" -name "*.o" -delete 2>/dev/null || true
find "${DEVEL_DIR}" -name "*.dtb" -delete 2>/dev/null || true
find "${DEVEL_DIR}" -name "*.dtbo" -delete 2>/dev/null || true
find "${DEVEL_DIR}" -name ".tmp_*" -delete 2>/dev/null || true
find "${DEVEL_DIR}" -name "*.tmp" -delete 2>/dev/null || true
find "${DEVEL_DIR}" -type d -empty -delete 2>/dev/null || true

# 同步关键生成文件的时间戳，避免外部模块编译时触发不必要的重编
if [ -f "${DEVEL_DIR}/include/generated/utsrelease.h" ]; then
  touch -r Makefile "${DEVEL_DIR}/include/generated/utsrelease.h"
fi
if [ -f "${DEVEL_DIR}/include/generated/autoconf.h" ]; then
  touch -r .config "${DEVEL_DIR}/include/generated/autoconf.h"
fi
if [ -f "${DEVEL_DIR}/include/config/auto.conf" ]; then
  touch -r .config "${DEVEL_DIR}/include/config/auto.conf"
fi

# 兜底：确保 auto.conf 存在
if [ ! -f "${DEVEL_DIR}/include/config/auto.conf" ]; then
  mkdir -p "${DEVEL_DIR}/include/config"
  cp .config "${DEVEL_DIR}/include/config/auto.conf"
fi

# 打包 kernel-devel
cd "${WORKDIR}"
tar -czf "${WORKDIR}/release/kernel-devel-OLK-6.6.tar.gz" kernel-devel

#==========================================================================#
#                        收尾工作                                           #
#==========================================================================#
# 归档构建日志
if [ -f "${LOG_FILE}" ]; then
  ls -alh "${LOG_FILE}"
  cp -a "${LOG_FILE}" "${WORKDIR}/release/"
fi

# 展示最终产物列表
echo ""
echo "=========================================="
echo "       构建产物清单 (${WORKDIR}/release)"
echo "=========================================="
ls -alh "${WORKDIR}/release/"
echo ""
echo "Build completed successfully!"
exit 0

