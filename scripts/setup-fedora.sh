#!/usr/bin/env bash
# MochiOS - Host Dependency Installer (Fedora / RHEL / CentOS)
set -euo pipefail

# Ensure root
[ "$(id -u)" -eq 0 ] || { echo "Run as root: sudo bash $0"; exit 1; }

echo "[MochiOS] Installing all dependencies..."

# Install development tools group
dnf groupinstall -y "Development Tools"

# Install all required packages
dnf install -y \
    gcc gcc-c++ make cmake ninja-build binutils bison flex gawk patch diffutils \
    git tcl gettext texinfo help2man pkgconfig libtool autoconf automake m4 \
    aria2 wget curl ca-certificates unzip jq zlib-devel bzip2-devel xz-devel \
    openssl-devel elfutils-libelf-devel ncurses-devel bc perl-devel cpio kmod \
    parted gdisk dosfstools e2fsprogs util-linux grub2-tools grub2-efi-x64 \
    mtools xorriso squashfs-tools dracut python3 python3-pip perl \
    qemu-system-x86 edk2-ovmf readline-devel sqlite groff gperf expect dejagnu \
    libcap-devel libcap-ng-devel audit-libs-devel pam-devel \
    gmp-devel mpfr-devel libmpc-devel isl-devel rsync which file

echo "============================================================"
echo "  MochiOS Host Ready (Fedora)."
echo "  Run 'bash scripts/buildworld.sh all' to start the build."
echo "============================================================"
