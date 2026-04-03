#!/usr/bin/env bash
# MochiOS - Host Dependency Installer (Arch Linux / Manjaro)
set -euo pipefail

# Ensure root
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

echo "[MochiOS] Installing all dependencies in one go..."

# Sync and install everything
pacman -Syu --noconfirm --needed \
    base-devel gcc g++ make cmake ninja binutils bison flex gawk patch diffutils coreutils file rsync git \
    gmp mpfr libmpc isl autoconf automake libtool m4 pkgconf texinfo help2man \
    aria2 wget curl ca-certificates unzip jq zlib bzip2 xz gzip tar zstd openssl \
    libelf ncurses bc pahole cpio kmod parted gptfdisk dosfstools e2fsprogs util-linux \
    grub efibootmgr mtools libisoburn squashfs-tools mkinitcpio python python-pip perl \
    qemu-system-x86 edk2-ovmf gettext readline sqlite groff gperf expect dejagnu \
    libcap libcap-ng audit pam

echo "============================================================"
echo "  MochiOS Host Ready."
echo "  Run 'bash scripts/buildworld.sh all' to start the build."
echo "============================================================"
