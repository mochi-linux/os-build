MochiOS
=======
A custom Linux-based operating system built entirely from source.

MochiOS is a handcrafted OS distribution assembled from upstream GNU/Linux
components. Every package — from the C library to the kernel — is compiled
from source using a clean cross-compilation toolchain and native chroot build.


FEATURES
--------
• Full system built from source (GCC, glibc, kernel, utilities)
• Custom init system (PID 1) written in C
• Distributed compilation support via Icecc
• Multiple distribution formats (tarball, disk image, SquashFS)
• Bootable UEFI disk images with GRUB
• Minimal system configuration included
• macOS-inspired directory structure (/System, /Library, /Users)


PROJECT STRUCTURE
-----------------
mochios/
  buildworld.sh               Main build orchestrator
  dist.sh                     Distribution creator (tarball/image/squashfs)
  umount-all.sh               Cleanup script for mounts and loop devices
  Makefile                    Convenience make targets
  SOURCES.txt                 Upstream package URLs and versions
  
  config/
    mochi.config              Linux kernel configuration
    etc/                      System configuration files
      fstab                   Filesystem mount table
      hostname                System hostname
      hosts                   Static hostname resolution
      passwd, group, shadow   User/group definitions
      profile                 System-wide shell profile
      os-release              OS identification
      inittab                 Init configuration
      nsswitch.conf           Name service switch config
  
  init/
    Makefile                  Init system build configuration
    src/
      init.c                  MochiOS init implementation (PID 1)
  
  scripts/
    setup-ubuntu.sh           Install host deps (Ubuntu/Debian)
    setup-arch.sh             Install host deps (Arch Linux/Manjaro)
    host/
      buildsource.sh          HOST cross-toolchain build
    chroot/
      buildsource.sh          CHROOT native package build


ROOTFS LAYOUT
-------------
The MochiOS filesystem follows a macOS-inspired directory structure:

  /System/                    Core OS files
    usr/bin                   User binaries
    usr/sbin                  System binaries
    usr/lib                   Shared libraries
    usr/include               Header files
    usr/share                 Architecture-independent data
    etc/                      System configuration
    Library/Kernel/           Kernel, initrd, GRUB bootloader
  /Applications/              User-installed applications
  /Library/                   Global shared libraries & frameworks
  /Users/                     User home directories
    Administrator/            Root/admin home  (← /root symlink)
  /Volumes/                   Mounted filesystems
  /dev, /proc, /sys           Virtual kernel filesystems

  Root-level compatibility symlinks (FHS-compatible):
    /bin   → System/usr/bin
    /sbin  → System/usr/sbin
    /usr   → System/usr
    /lib   → System/lib
    /lib64 → System/lib64
    /etc   → System/etc
    /boot  → System/Library/Kernel
    /root  → Users/Administrator


BUILD PIPELINE
--------------
Step 1  HOST: headers
        Install Linux kernel headers to the cross-sysroot.

Step 2  HOST: binutils
        Build cross binutils (assembler, linker) targeting x86_64-mochios-linux-gnu.

Step 3  HOST: gcc (stage 1)
        Build a minimal cross GCC without a C library (--with-newlib).

Step 4  HOST: glibc
        Cross-compile GNU C Library against the stage-1 GCC.

Step 5  HOST: gcc (stage 2)
        Build a full cross GCC with glibc support, PIE and SSP enabled.

Step 6  CHROOT: bash
        Build GNU Bash as the primary shell.

Step 7  CHROOT: coreutils
        Build GNU Coreutils (ls, cp, mv, rm, etc.).

Step 8  CHROOT: system utilities
        Build essential system utilities:
          • ncurses, zlib, xz, gzip, tar, findutils
          • util-linux, inetutils
          • perl, autoconf, automake, libtool
          • openssl (for crypto support)
          • bison, flex (for kernel build)
          • elfutils (libelf for kernel objtool)
          • make
          • MochiOS init system (custom PID 1)

Step 9  CHROOT: kernel
        Configure and compile Linux kernel with custom config.
        Kernel image → /System/Library/Kernel/vmlinuz
        Modules → /lib/modules/

Step 10 DISTRIBUTION
        Create distribution artifacts:
          • Compressed tarball (.tar.xz)
          • Bootable disk image (.img) with GPT + UEFI
          • SquashFS image (.squashfs) for live systems


REQUIREMENTS
------------
Host system:   Linux (x86_64), WSL2, or equivalent
Disk space:    ~20 GB for sources + build tree
RAM:           4 GB minimum, 8 GB recommended
CPU:           Multi-core recommended (JOBS=nproc by default)

Host tools required (installed by setup scripts):
  gcc, g++, make, bison, flex, gawk, texinfo
  libgmp-dev, libmpfr-dev, libmpc-dev, libisl-dev
  parted, dosfstools, e2fsprogs, grub-efi, rsync
  wget or curl


QUICK START
-----------
  1. Install host dependencies:

       Ubuntu/Debian:    sudo bash scripts/setup-ubuntu.sh
       Arch/Manjaro:     sudo bash scripts/setup-arch.sh

  2. Run the full build:

       bash buildworld.sh all

     Or step by step:

       bash buildworld.sh fetch        # Download all source packages
       bash buildworld.sh rootfs       # Create rootfs directory structure
       bash buildworld.sh host         # Build cross-compilation toolchain
       sudo bash buildworld.sh chroot  # Build system in chroot environment

  3. Create distribution artifacts:

       sudo bash dist.sh image         # Create bootable disk image
       sudo bash dist.sh squashfs      # Create SquashFS image
       sudo bash dist.sh tarball       # Create compressed tarball
       sudo bash dist.sh all           # Create all formats

  4. Test in QEMU:

       qemu-system-x86_64 -enable-kvm -m 2G \
         -drive file=dist/mochios-YYYYMMDD.img,format=raw \
         -bios /usr/share/ovmf/OVMF.fd

  5. Write to USB drive:

       sudo dd if=dist/mochios-YYYYMMDD.img of=/dev/sdX bs=4M status=progress
       sync

  6. Via Make:

       make               # full pipeline
       make host          # cross-toolchain only
       make chroot        # chroot build only (sudo)
       make image         # disk image only  (sudo)
       make help          # show all targets


BUILD MODES
-----------
MochiOS supports different build modes for compilation:

  --host           Local build (default)
  --cluster        Distributed build via Icecc

  Example:
    bash buildworld.sh --cluster host    # Build toolchain with Icecc
    sudo bash buildworld.sh --cluster chroot


ENVIRONMENT VARIABLES
---------------------
  MOCHI_BUILD      Build root directory  (default: ./buildfs)
  MOCHI_SOURCES    Source packages       (default: $MOCHI_BUILD/sources)
  MOCHI_SYSROOT    Cross sysroot         (default: $MOCHI_BUILD/sysroot)
  MOCHI_ROOTFS     Chroot rootfs         (default: $MOCHI_BUILD/rootfs)
  MOCHI_CROSS      Cross toolchain       (default: $MOCHI_BUILD/cross)
  MOCHI_TARGET     Cross triplet         (default: x86_64-mochios-linux-gnu)
  JOBS             Parallel jobs         (default: nproc*2+8)
  IMAGE_SIZE       Disk image size       (default: 1G)
  DIST_VERSION     Distribution version  (default: YYYYMMDD)

  Example:
    MOCHI_BUILD=/data/mochi JOBS=16 bash buildworld.sh host
    IMAGE_SIZE=8G sudo bash dist.sh image


TESTING THE IMAGE
-----------------
  qemu-system-x86_64 \
    -m 2G \
    -bios /usr/share/ovmf/OVMF.fd \
    -drive file=/mnt/mochi-build/mochios.img,format=raw \
    -nographic


SOURCE PACKAGES
---------------
See SOURCES.txt for the full list of upstream packages and download URLs.

  Core:        Linux 7.0-rc5, Glibc 2.43, GCC 15.2.0, Binutils 2.46.0
  Shell:       Bash 5.3, Coreutils 9.10, Findutils 4.10.0
  Libs:        Ncurses 6.4, Zlib 1.3.2, XZ 5.8.2, OpenSSL 3.6.1
  Boot:        GRUB (host-installed), Linux kernel modules via kmod 34
  GCC prereqs: MPFR 4.2.1, MPC 1.3.1, ISL 0.27


LICENSE
-------
The MochiOS build scripts and configuration files are released under the
MIT License. See LICENSE.txt for details.

Each upstream package retains its own license:
  - Linux kernel          GPLv2
  - GNU components        GPLv2 or later / LGPLv2.1 or later
  - OpenSSL               Apache License 2.0
  - Individual packages   See each package's LICENSE / COPYING file
