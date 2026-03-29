#!/usr/bin/env bash
# MochiOS - Host Dependency Installer (Arch Linux / Manjaro)
# Tested on: Arch Linux (rolling), Manjaro

set -euo pipefail

log() { echo "[SETUP] $(date '+%H:%M:%S')  $*"; }
die() { echo "[SETUP] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"

log "MochiOS Host Dependency Setup (Arch Linux)"
log "Updating package database ..."
pacman -Sy --noconfirm

# ---------------------------------------------------------------------------
# Core build tools
# ---------------------------------------------------------------------------
log "Installing core build tools ..."
pacman -S --noconfirm --needed \
    base-devel \
    gcc \
    g++ \
    make \
    cmake \
    ninja \
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
# Cross-compilation prerequisites (GCC needs GMP, MPFR, MPC, ISL)
# ---------------------------------------------------------------------------
log "Installing GCC prerequisites ..."
pacman -S --noconfirm --needed \
    gmp \
    mpfr \
    libmpc \
    isl

# ---------------------------------------------------------------------------
# Autotools & build infrastructure
# ---------------------------------------------------------------------------
log "Installing autotools & build infra ..."
pacman -S --noconfirm --needed \
    autoconf \
    automake \
    libtool \
    m4 \
    pkgconf \
    texinfo \
    help2man

# ---------------------------------------------------------------------------
# Source download tools
# ---------------------------------------------------------------------------
log "Installing download tools ..."
pacman -S --noconfirm --needed \
    aria2 \
    wget \
    curl \
    ca-certificates \
    unzip

# ---------------------------------------------------------------------------
# Compression libraries & tools
# ---------------------------------------------------------------------------
log "Installing compression tools ..."
pacman -S --noconfirm --needed \
    zlib \
    bzip2 \
    xz \
    gzip \
    tar \
    zstd

# ---------------------------------------------------------------------------
# SSL / security libraries
# ---------------------------------------------------------------------------
log "Installing SSL libraries ..."
pacman -S --noconfirm --needed \
    openssl

# ---------------------------------------------------------------------------
# Linux kernel build dependencies
# ---------------------------------------------------------------------------
log "Installing kernel build dependencies ..."
pacman -S --noconfirm --needed \
    libelf \
    ncurses \
    bc \
    pahole \
    cpio \
    kmod

# ---------------------------------------------------------------------------
# Disk image & bootloader tools
# ---------------------------------------------------------------------------
log "Installing disk image & bootloader tools ..."
pacman -S --noconfirm --needed \
    parted \
    gptfdisk \
    dosfstools \
    e2fsprogs \
    util-linux \
    grub \
    efibootmgr \
    mtools

# ---------------------------------------------------------------------------
# Initramfs generator
# ---------------------------------------------------------------------------
log "Installing initramfs generator ..."
pacman -S --noconfirm --needed \
    mkinitcpio \
    dracut || log "  dracut not available, mkinitcpio will be used"

# ---------------------------------------------------------------------------
# Python & Perl (required by configure scripts and kernel build)
# ---------------------------------------------------------------------------
log "Installing Python & Perl ..."
pacman -S --noconfirm --needed \
    python \
    python-pip \
    perl

# ---------------------------------------------------------------------------
# QEMU (optional – for testing the generated image)
# ---------------------------------------------------------------------------
log "Installing QEMU (optional, for testing) ..."
pacman -S --noconfirm --needed \
    qemu-system-x86 \
    edk2-ovmf || log "  QEMU install skipped (not critical)"

# ---------------------------------------------------------------------------
# Miscellaneous tools needed by various configure scripts
# ---------------------------------------------------------------------------
log "Installing misc tools ..."
pacman -S --noconfirm --needed \
    gettext \
    readline \
    sqlite \
    groff \
    gperf \
    expect \
    dejagnu \
    libcap \
    libcap-ng \
    audit \
    pam

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
