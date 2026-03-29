##############################################################################
# MochiOS Build System – Makefile
# Wraps buildworld.sh for convenient make targets.
#
# Usage:
#   make              # Full build pipeline
#   make fetch        # Download all sources
#   make host         # Build cross toolchain
#   make chroot       # Build inside chroot  (requires root)
#   make image        # Create bootable disk image  (requires root)
#   make shell        # Enter interactive chroot  (requires root)
#   make clean        # Remove build artifacts
#   make distclean    # Remove everything
#
# Override variables:
#   make host JOBS=16
#   make all  MOCHI_BUILD=/custom/path
##############################################################################

SHELL      := /usr/bin/env bash
BUILD      ?= buildworld.sh
JOBS       ?= $(shell nproc)

MOCHI_BUILD   ?= $(CURDIR)/buildfs
MOCHI_TARGET  ?= x86_64-mochios-linux-gnu
MOCHI_IMAGE   ?= $(MOCHI_BUILD)/mochios.img
IMG_SIZE_MB   ?= 4096
EFI_SIZE_MB   ?= 512

export MOCHI_BUILD MOCHI_TARGET MOCHI_IMAGE IMG_SIZE_MB EFI_SIZE_MB JOBS

.PHONY: all fetch rootfs host populate chroot image shell \
        clean distclean \
        host-headers host-binutils host-gcc1 host-glibc host-gcc2 \
        chroot-bash chroot-coreutils chroot-system chroot-kernel chroot-grub \
        help

##############################################################################
# Primary targets
##############################################################################

all: fetch rootfs host populate chroot image

fetch:
	bash $(BUILD) fetch

rootfs:
	bash $(BUILD) rootfs

host:
	bash $(BUILD) host all

populate:
	bash $(BUILD) populate

chroot:
	sudo bash $(BUILD) chroot all

image:
	sudo bash $(BUILD) image

shell:
	sudo bash $(BUILD) shell

##############################################################################
# Individual HOST steps
##############################################################################

host-headers:
	bash $(BUILD) host headers

host-binutils:
	bash $(BUILD) host binutils

host-gcc1:
	bash $(BUILD) host gcc1

host-glibc:
	bash $(BUILD) host glibc

host-gcc2:
	bash $(BUILD) host gcc2

##############################################################################
# Individual CHROOT steps
##############################################################################

chroot-bash:
	sudo bash $(BUILD) chroot bash

chroot-coreutils:
	sudo bash $(BUILD) chroot coreutils

chroot-system:
	sudo bash $(BUILD) chroot system

chroot-kernel:
	sudo bash $(BUILD) chroot kernel

chroot-grub:
	sudo bash $(BUILD) chroot grub

##############################################################################
# Maintenance
##############################################################################

clean:
	bash $(BUILD) clean

distclean:
	bash $(BUILD) distclean

##############################################################################
# Help
##############################################################################

help:
	@echo ""
	@echo "MochiOS Build System"
	@echo "════════════════════════════════════════════════"
	@echo ""
	@echo "Primary targets:"
	@echo "  make all             Full pipeline (fetch→rootfs→host→populate→chroot→image)"
	@echo "  make fetch           Download and extract all sources"
	@echo "  make rootfs          Create MochiOS rootfs directory layout"
	@echo "  make host            Build entire cross toolchain"
	@echo "  make populate        Cross-compile bash+coreutils into rootfs; copy glibc libs"
	@echo "  make chroot          Build all chroot packages  (sudo)"
	@echo "  make image           Create bootable disk image  (sudo)"
	@echo "  make shell           Interactive MochiOS chroot shell  (sudo)"
	@echo ""
	@echo "HOST steps (in order):"
	@echo "  make host-headers    Linux kernel headers"
	@echo "  make host-binutils   Cross binutils"
	@echo "  make host-gcc1       GCC stage 1 (no libc)"
	@echo "  make host-glibc      Glibc (cross-compiled)"
	@echo "  make host-gcc2       GCC stage 2 (full)"
	@echo ""
	@echo "CHROOT steps (in order):"
	@echo "  make chroot-bash       Bash"
	@echo "  make chroot-coreutils  Coreutils"
	@echo "  make chroot-system     System utilities"
	@echo "  make chroot-kernel     Linux kernel + modules"
	@echo "  make chroot-grub       GRUB config"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean           Remove build artifacts (keep sources)"
	@echo "  make distclean       Remove everything"
	@echo ""
	@echo "Variables:"
	@echo "  MOCHI_BUILD=$(MOCHI_BUILD)  (default: ./buildfs)"
	@echo "  MOCHI_TARGET=$(MOCHI_TARGET)"
	@echo "  MOCHI_IMAGE=$(MOCHI_IMAGE)"
	@echo "  IMG_SIZE_MB=$(IMG_SIZE_MB)"
	@echo "  EFI_SIZE_MB=$(EFI_SIZE_MB)"
	@echo "  JOBS=$(JOBS)"
	@echo ""
