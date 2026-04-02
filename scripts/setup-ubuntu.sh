#!/usr/bin/env bash
# MochiOS - Host Dependency Installer (Ubuntu / Debian)
set -euo pipefail

# Ensure root
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

echo "[MochiOS] Updating and installing all dependencies..."

# Update repositories first
apt-get update

# Install everything in one transaction
apt-get install -y --no-install-recommends \
    build-essential gcc g++ make cmake ninja-build binutils bison flex gawk patch diffutils \
    git tcl gettext texinfo help2man pkg-config libtool autoconf automake m4 \
    aria2 wget curl ca-certificates unzip jq zlib1g-dev libbz2-dev liblzma-dev \
    libssl-dev libelf-dev libncurses-dev bc pahole cpio kmod \
    parted gdisk dosfstools e2fsprogs util-linux grub-pc-bin grub-efi-amd64-bin \
    mtools xorriso squashfs-tools initramfs-tools python3 python3-pip perl \
    qemu-system-x86 ovmf readline-common sqlite3 groff gperf expect dejagnu \
    libcap-dev libcap-ng-dev libaudit-dev libpam0g-dev

echo "============================================================"
echo "  MochiOS Host Ready (Ubuntu)."
echo "  Run 'bash buildworld.sh all' to start the build."
echo "============================================================"