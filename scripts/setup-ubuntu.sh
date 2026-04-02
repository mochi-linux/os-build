#!/usr/bin/env bash
# MochiOS - Host Dependency Installer (Ubuntu / Debian)
# Tested on: Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 12

set -euo pipefail

log() { echo "[SETUP] $(date '+%H:%M:%S')  $*"; }
die() { echo "[SETUP] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"

log "MochiOS Host Dependency Setup (Ubuntu/Debian)"
log "Updating package lists ..."
apt-get update -qq

# ---------------------------------------------------------------------------
# Core build tools
# ---------------------------------------------------------------------------
log "Installing core build tools ..."
apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    ninja-build \
    binutils \
    bison \
    flex \
    gawk \
    patch \
    diffutils \
    coreutils \
    file \
    rsync \
    git

# ---------------------------------------------------------------------------
# Cross-compilation prerequisites (GCC needs GMP, MPFR, MPC)
# ---------------------------------------------------------------------------
log "Installing GCC prerequisites ..."
apt-get install -y --no-install-recommends \
    libgmp-dev \
    libmpfr-dev \
    libmpc-dev \
    libisl-dev

# ---------------------------------------------------------------------------
# Autotools & build infrastructure
# ---------------------------------------------------------------------------
log "Installing autotools & build infra ..."
apt-get install -y --no-install-recommends \
    autoconf \
    automake \
    libtool \
    m4 \
    pkg-config \
    texinfo \
    help2man

# ---------------------------------------------------------------------------
# Source download tools
# ---------------------------------------------------------------------------
log "Installing download tools ..."
apt-get install -y --no-install-recommends \
    aria2 \
    wget \
    curl \
    ca-certificates \
    unzip \
    jq

# ---------------------------------------------------------------------------
# Compression libraries & tools
# ---------------------------------------------------------------------------
log "Installing compression tools ..."
apt-get install -y --no-install-recommends \
    zlib1g-dev \
    libbz2-dev \
    liblzma-dev \
    xz-utils \
    gzip \
    tar \
    zstd \
    libzstd-dev

# ---------------------------------------------------------------------------
# SSL / security libraries
# ---------------------------------------------------------------------------
log "Installing SSL libraries ..."
apt-get install -y --no-install-recommends \
    libssl-dev \
    openssl

# ---------------------------------------------------------------------------
# Linux kernel build dependencies
# ---------------------------------------------------------------------------
log "Installing kernel build dependencies ..."
apt-get install -y --no-install-recommends \
    libelf-dev \
    libncurses-dev \
    libncurses5-dev \
    bc \
    dwarves \
    pahole \
    cpio \
    kmod

# ---------------------------------------------------------------------------
# Disk image & bootloader tools
# ---------------------------------------------------------------------------
log "Installing disk image & bootloader tools ..."
apt-get install -y --no-install-recommends \
    parted \
    gdisk \
    dosfstools \
    e2fsprogs \
    util-linux \
    losetup \
    grub-efi-amd64-bin \
    grub-pc-bin \
    grub-common \
    mtools \
    xorriso \
    squashfs-tools

# ---------------------------------------------------------------------------
# Initramfs generators (use dracut or mkinitcpio)
# ---------------------------------------------------------------------------
log "Installing initramfs generator ..."
if apt-cache show dracut >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends dracut dracut-core
else
    log "  dracut not available, skipping (install manually if needed)"
fi

# ---------------------------------------------------------------------------
# Python & Perl (required by some configure scripts and kernel build)
# ---------------------------------------------------------------------------
log "Installing Python & Perl ..."
apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    perl \
    perl-modules

# ---------------------------------------------------------------------------
# QEMU (optional – for testing the generated image)
# ---------------------------------------------------------------------------
log "Installing QEMU (optional, for testing) ..."
apt-get install -y --no-install-recommends \
    qemu-system-x86 \
    ovmf || log "  QEMU install skipped (not critical)"

# ---------------------------------------------------------------------------
# Miscellaneous tools needed by various configure scripts
# ---------------------------------------------------------------------------
log "Installing misc tools ..."
apt-get install -y --no-install-recommends \
    gettext \
    libreadline-dev \
    libsqlite3-dev \
    groff \
    gperf \
    expect \
    dejagnu \
    systemtap-sdt-dev \
    libcap-dev \
    libcap-ng-dev \
    libaudit-dev \
    libpam-dev \
    libsystemd-dev || true

# ---------------------------------------------------------------------------
# WSL-specific: ensure loop device support
# ---------------------------------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null; then
    log "WSL detected – ensuring loop device module ..."
    modprobe loop 2>/dev/null || \
        log "  NOTE: loop module not available in this WSL kernel."
    log "  For disk image creation in WSL, WSL2 with a custom kernel"
    log "  or a native Linux VM is recommended."
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "============================================================"
log "  All dependencies installed successfully."
log ""
log "  Next steps:"
log "    1. Fetch sources  : bash buildworld.sh fetch"
log "    2. Set up rootfs  : bash buildworld.sh rootfs"
log "    3. Build toolchain: bash buildworld.sh host"
log "    4. Chroot build   : sudo bash buildworld.sh chroot"
log "    5. Create image   : sudo bash buildworld.sh image"
log ""
log "  Or run everything:  bash buildworld.sh all"
log "  Or via make:        make"
log "============================================================"
