MochiOS
=======
A custom Linux-based operating system built entirely from source.

MochiOS is a handcrafted OS distribution assembled from upstream GNU/Linux
components. Every package — from the C library to the bootloader — is
compiled from source using a clean cross-compilation toolchain.


PROJECT STRUCTURE
-----------------
mochios/
  buildworld.sh               Main build orchestrator
  buildworld-wsl.ps1          Windows WSL launcher
  Makefile                    Convenience make targets
  SOURCES.txt                 Upstream package URLs and versions
  rootfs.txt                  Filesystem layout reference
  scripts/
    setup-ubuntu.sh           Install host deps (Ubuntu/Debian)
    setup-arch.sh             Install host deps (Arch Linux/Manjaro)
    host/
      buildsource.sh          HOST cross-toolchain build
      createimage.sh          Bootable disk image creator
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

Step 8  CHROOT: system
        Build system utilities:
          ncurses, zlib, xz, gzip, tar, findutils,
          util-linux, inetutils, kmod, make

Step 9  CHROOT: kernel
        Configure and compile the Linux kernel, install modules.
        Kernel image → /System/Library/Kernel/vmlinuz

Step 10 CHROOT: grub
        Write GRUB configuration for EFI booting.

Step 11 IMAGE
        Create a bootable GPT disk image:
          Partition 1 – FAT32 EFI System Partition  (512 MiB)
          Partition 2 – ext4 root partition          (remaining space)


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

       bash buildworld.sh fetch
       bash buildworld.sh rootfs
       bash buildworld.sh host
       sudo bash buildworld.sh chroot
       sudo bash buildworld.sh image

  3. From Windows (WSL):

       .\buildworld-wsl.ps1 -Command all

  4. Via Make:

       make               # full pipeline
       make host          # cross-toolchain only
       make chroot        # chroot build only (sudo)
       make image         # disk image only  (sudo)
       make help          # show all targets


ENVIRONMENT VARIABLES
---------------------
  MOCHI_BUILD      Build root directory  (default: /mnt/mochi-build)
  MOCHI_TARGET     Cross triplet         (default: x86_64-mochios-linux-gnu)
  MOCHI_IMAGE      Output image path     (default: $MOCHI_BUILD/mochios.img)
  IMG_SIZE_MB      Disk image size MiB   (default: 4096)
  EFI_SIZE_MB      EFI partition MiB     (default: 512)
  JOBS             Parallel jobs         (default: nproc)

  Example:
    MOCHI_BUILD=/data/mochi JOBS=16 bash buildworld.sh host


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
