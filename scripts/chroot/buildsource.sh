#!/usr/bin/env bash
# MochiOS - Chroot Build Script
# Build order: bash → coreutils → system → kernel → grub
#
# Designed to run INSIDE the MochiOS chroot environment where:
#   /          = rootfs
#   /sources   = host sources directory (bind-mounted)
#   /build     = temporary build directory (bind-mounted)

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
: "${MOCHI_SOURCES:=/sources}"
: "${MOCHI_BUILD:=/build}"
: "${JOBS:=$(nproc)}"
: "${BUILD_MODE:=host}"  # host or cluster

# Package versions (mirror SOURCES.txt)
LINUX_VER="7.0-rc5"
BASH_VER="5.3"
COREUTILS_VER="9.10"
UTIL_LINUX_VER="2.40"
FINDUTILS_VER="4.10.0"
INETUTILS_VER="2.5"
MAKE_VER="4.4"
NCURSES_VER="6.4"
ZLIB_VER="1.3.2"
XZ_VER="5.8.2"
GZIP_VER="1.14"
TAR_VER="1.35"
KMOD_VER="34"
PERL_VER="5.42.1"
AUTOCONF_VER="2.73"
AUTOMAKE_VER="1.17"
LIBTOOL_VER="2.5.4"
OPENSSL_VER="3.4.0"
BISON_VER="3.8.2"
FLEX_VER="2.6.4"
ELFUTILS_VER="0.192"
NANO_VER="7.2"
HTOP_VER="3.4.1"

BOOT_DIR="/System/Library/Kernel"

# ---------------------------------------------------------------------------
# Build Mode Configuration
# ---------------------------------------------------------------------------
setup_build_mode() {
    case "$BUILD_MODE" in
        host)
            log "Build mode: HOST (local build)"
            MAKE_CC=""
            CONFIGURE_CC=""
            KERNEL_CC=""
            ;;
        cluster)
            if ! command -v icecc >/dev/null 2>&1; then
                die "icecc not found. Install icecc for cluster builds."
            fi
            log "Build mode: CLUSTER (icecc distributed build)"
            log "  icecc version: $(icecc --version 2>&1 | head -n1)"
            MAKE_CC="CC=\"icecc gcc\""
            CONFIGURE_CC="CC=\"icecc gcc\""
            KERNEL_CC="CC=\"icecc gcc\""
            ;;
        *)
            die "Unknown BUILD_MODE: $BUILD_MODE (use 'host' or 'cluster')"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[CHROOT] $(date '+%H:%M:%S')  $*"; }
die() { echo "[CHROOT] ERROR: $*" >&2; exit 1; }
hdr() {
    echo
    echo "──────────────────────────────────────────────────────────"
    echo "  $*"
    echo "──────────────────────────────────────────────────────────"
}

require_src() {
    [ -d "$1" ] || die "Source directory not found: $1"
}

# Build state tracking
STATE_DIR="$MOCHI_BUILD/.buildstate"
mkdir -p "$STATE_DIR"

mark_built() {
    local component="$1"
    touch "$STATE_DIR/chroot-${component}.done"
    log "✓ $component build completed"
}

is_built() {
    local component="$1"
    [ -f "$STATE_DIR/chroot-${component}.done" ]
}

skip_if_built() {
    local component="$1"
    if is_built "$component"; then
        log "⊳ Skipping $component (already built)"
        return 0
    fi
    return 1
}

conf_build() {
    local src="$1"; shift
    local bld="$1"; shift
    require_src "$src"
    rm -rf "$bld" && mkdir -p "$bld"
    cd "$bld"
    eval "$CONFIGURE_CC" "$src/configure" "$@"
}

# ---------------------------------------------------------------------------
# Step 1 – Bash
# ---------------------------------------------------------------------------
build_bash() {
    skip_if_built "bash" && return 0
    hdr "[1/5] Bash $BASH_VER"
    local src="$MOCHI_SOURCES/bash-$BASH_VER"
    local bld="$MOCHI_BUILD/build-bash"

    conf_build "$src" "$bld" \
        --prefix=/usr \
        --without-bash-malloc \
        --docdir=/usr/share/doc/bash

    eval make -j"$JOBS" $MAKE_CC
    make install

    ln -sfn bash /usr/bin/sh

    log "Bash installed → /usr/bin/bash, /usr/bin/sh"
    mark_built "bash"
}

# ---------------------------------------------------------------------------
# Step 2 – Coreutils
# ---------------------------------------------------------------------------
build_coreutils() {
    skip_if_built "coreutils" && return 0
    hdr "[2/5] Coreutils $COREUTILS_VER"
    local src="$MOCHI_SOURCES/coreutils-$COREUTILS_VER"
    local bld="$MOCHI_BUILD/build-coreutils"

    FORCE_UNSAFE_CONFIGURE=1 \
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --enable-no-install-program=kill,uptime \
        --docdir=/usr/share/doc/coreutils

    eval make -j"$JOBS" $MAKE_CC
    make install

    log "Coreutils installed → /usr/bin"
    mark_built "coreutils"
}

# ---------------------------------------------------------------------------
# Step 3 – System Utilities
#   ncurses → zlib → xz → gzip → tar → findutils →
#   util-linux → inetutils → perl → autoconf → kmod → make
# ---------------------------------------------------------------------------
build_system() {
    hdr "[3/5] System Utilities"

    # --- Ncurses ---
    if ! skip_if_built "ncurses"; then
    log "  -> Ncurses $NCURSES_VER"
    local src bld
    src="$MOCHI_SOURCES/ncurses-$NCURSES_VER"
    bld="$MOCHI_BUILD/build-ncurses"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --mandir=/usr/share/man \
        --with-shared \
        --enable-widec \
        --without-debug \
        --without-normal \
        --without-cxx \
        --without-cxx-binding \
        --enable-pc-files \
        --with-pkg-config-libdir=/usr/lib/pkgconfig
    eval make -j"$JOBS" $MAKE_CC
    make install
    for hdr in curses.h ncurses.h term.h termcap.h; do
        if [ -e "/usr/include/ncursesw/$hdr" ] && [ ! -e "/usr/include/$hdr" ]; then
            ln -sfn "ncursesw/$hdr" "/usr/include/$hdr" 2>/dev/null || true
        fi
    done
    # Ensure libncursesw → libncurses compat links
    for lib in ncurses form panel menu; do
        ln -sfn "lib${lib}w.so" "/usr/lib/lib${lib}.so" 2>/dev/null || true
    done
    ln -sfn libncursesw.so /usr/lib/libcurses.so 2>/dev/null || true
    mark_built "ncurses"
    fi

    # --- Zlib ---
    if ! skip_if_built "zlib"; then
    log "  -> Zlib $ZLIB_VER"
    src="$MOCHI_SOURCES/zlib-$ZLIB_VER"
    bld="$MOCHI_BUILD/build-zlib"
    require_src "$src"
    rm -rf "$bld" && mkdir -p "$bld"
    cd "$bld"
    eval "$CONFIGURE_CC" "$src/configure" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "zlib"
    fi

    # --- XZ Utils ---
    if ! skip_if_built "xz"; then
    log "  -> XZ Utils $XZ_VER"
    src="$MOCHI_SOURCES/xz-$XZ_VER"
    bld="$MOCHI_BUILD/build-xz"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --disable-static \
        --docdir=/usr/share/doc/xz
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "xz"
    fi

    # --- Gzip ---
    if ! skip_if_built "gzip"; then
    log "  -> Gzip $GZIP_VER"
    src="$MOCHI_SOURCES/gzip-$GZIP_VER"
    bld="$MOCHI_BUILD/build-gzip"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "gzip"
    fi

    # --- Tar ---
    if ! skip_if_built "tar"; then
    log "  -> Tar $TAR_VER"
    src="$MOCHI_SOURCES/tar-$TAR_VER"
    bld="$MOCHI_BUILD/build-tar"
    FORCE_UNSAFE_CONFIGURE=1 \
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --without-python
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "tar"
    fi

    # --- Findutils ---
    if ! skip_if_built "findutils"; then
    log "  -> Findutils $FINDUTILS_VER"
    src="$MOCHI_SOURCES/findutils-$FINDUTILS_VER"
    bld="$MOCHI_BUILD/build-findutils"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --localstatedir=/var/lib/locate \
        --docdir=/usr/share/doc/findutils
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "findutils"
    fi

    # --- Util-linux ---
    if ! skip_if_built "util-linux"; then
    log "  -> Util-linux $UTIL_LINUX_VER"
    
    # Create root user/group if they don't exist (required for mount utility)
    getent group root >/dev/null 2>&1 || groupadd -g 0 root
    getent passwd root >/dev/null 2>&1 || useradd -u 0 -g 0 -d /root -s /bin/bash root
    
    # Create tty group if it doesn't exist (required for wall utility)
    getent group tty >/dev/null 2>&1 || groupadd -g 5 tty
    
    src="$MOCHI_SOURCES/util-linux-$UTIL_LINUX_VER"
    bld="$MOCHI_BUILD/build-util-linux"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --sbindir=/usr/sbin \
        --libdir=/usr/lib \
        --runstatedir=/run \
        --disable-chfn-chsh \
        --disable-login \
        --disable-nologin \
        --disable-su \
        --disable-setpriv \
        --disable-runuser \
        --disable-pylibmount \
        --disable-static \
        --disable-liblastlog2 \
        --disable-lsfd \
        --without-python \
        ADJTIME_PATH=/var/lib/hwclock/adjtime \
        --docdir=/usr/share/doc/util-linux
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "util-linux"
    fi

    # --- Inetutils ---
    if ! skip_if_built "inetutils"; then
    log "  -> Inetutils $INETUTILS_VER"
    src="$MOCHI_SOURCES/inetutils-$INETUTILS_VER"
    bld="$MOCHI_BUILD/build-inetutils"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --bindir=/usr/bin \
        --localstatedir=/var \
        --disable-logger \
        --disable-whois \
        --disable-rcp \
        --disable-rexec \
        --disable-rlogin \
        --disable-rsh \
        --disable-telnet \
        --disable-telnetd \
        --disable-servers
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "inetutils"
    fi

    # --- Perl ---
    if ! skip_if_built "perl"; then
    log "  -> Perl $PERL_VER"
    src="$MOCHI_SOURCES/perl-$PERL_VER"
    require_src "$src"
    cd "$src"
    
    # Clean any previous build
    [ -f Makefile ] && make distclean 2>/dev/null || true
    
    # Perl requires in-tree build
    ./Configure -des \
        -Dprefix=/usr \
        -Dvendorprefix=/usr \
        -Dprivlib=/usr/lib/perl5/core_perl \
        -Darchlib=/usr/lib/perl5/core_perl \
        -Dsitelib=/usr/lib/perl5/site_perl \
        -Dsitearch=/usr/lib/perl5/site_perl \
        -Dvendorlib=/usr/lib/perl5/vendor_perl \
        -Dvendorarch=/usr/lib/perl5/vendor_perl \
        -Dman1dir=/usr/share/man/man1 \
        -Dman3dir=/usr/share/man/man3 \
        -Duseshrplib \
        -Dusethreads
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "perl"
    fi

    # --- Autoconf ---
    if ! skip_if_built "autoconf"; then
    log "  -> Autoconf $AUTOCONF_VER"
    src="$MOCHI_SOURCES/autoconf-$AUTOCONF_VER"
    bld="$MOCHI_BUILD/build-autoconf"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "autoconf"
    fi

    # --- Automake ---
    if ! skip_if_built "automake"; then
    log "  -> Automake $AUTOMAKE_VER"
    src="$MOCHI_SOURCES/automake-$AUTOMAKE_VER"
    bld="$MOCHI_BUILD/build-automake"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "automake"
    fi

    # --- Libtool ---
    if ! skip_if_built "libtool"; then
    log "  -> Libtool $LIBTOOL_VER"
    src="$MOCHI_SOURCES/libtool-$LIBTOOL_VER"
    bld="$MOCHI_BUILD/build-libtool"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "libtool"
    fi

    # --- OpenSSL ---
    if ! skip_if_built "openssl"; then
    log "  -> OpenSSL $OPENSSL_VER"
    src="$MOCHI_SOURCES/openssl-$OPENSSL_VER"
    require_src "$src"
    cd "$src"
    
    # Clean any previous build
    [ -f Makefile ] && make distclean 2>/dev/null || true
    
    # OpenSSL requires in-tree build with custom Configure script
    ./Configure linux-x86_64 \
        --prefix=/usr \
        --openssldir=/etc/ssl \
        --libdir=lib \
        shared \
        zlib-dynamic
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "openssl"
    fi

    # --- Kmod ---
    # SKIPPED: kmod has complex autotools dependencies
    # The kernel modules can be managed manually if needed
    log "  -> Kmod $KMOD_VER (SKIPPED - optional)"

    # --- Bison ---
    if ! skip_if_built "bison"; then
    log "  -> Bison $BISON_VER"
    src="$MOCHI_SOURCES/bison-$BISON_VER"
    bld="$MOCHI_BUILD/build-bison"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --docdir=/usr/share/doc/bison
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "bison"
    fi

    # --- Flex ---
    if ! skip_if_built "flex"; then
    log "  -> Flex $FLEX_VER"
    src="$MOCHI_SOURCES/flex-$FLEX_VER"
    bld="$MOCHI_BUILD/build-flex"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --docdir=/usr/share/doc/flex
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "flex"
    fi

    # --- Elfutils ---
    if ! skip_if_built "elfutils"; then
    log "  -> Elfutils $ELFUTILS_VER"
    src="$MOCHI_SOURCES/elfutils-$ELFUTILS_VER"
    bld="$MOCHI_BUILD/build-elfutils"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --disable-debuginfod \
        --enable-libdebuginfod=dummy
    # Build with -Wno-error to avoid const qualifier warnings
    eval make -j"$JOBS" $MAKE_CC CFLAGS=\"-g -O2 -Wno-error\"
    make install
    mark_built "elfutils"
    fi

    # --- Make ---
    if ! skip_if_built "make"; then
    log "  -> Make $MAKE_VER"
    src="$MOCHI_SOURCES/make-$MAKE_VER"
    bld="$MOCHI_BUILD/build-make"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --without-guile \
        --docdir=/usr/share/doc/make
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "make"
    fi

    # --- Nano ---
    if ! skip_if_built "nano"; then
    log "  -> Nano $NANO_VER"
    src="$MOCHI_SOURCES/nano-$NANO_VER"
    bld="$MOCHI_BUILD/build-nano"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --sysconfdir=/etc \
        --enable-utf8 \
        --docdir=/usr/share/doc/nano
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "nano"
    fi

    # --- Htop ---
    if ! skip_if_built "htop"; then
    log "  -> Htop $HTOP_VER"
    src="$MOCHI_SOURCES/htop-$HTOP_VER"
    bld="$MOCHI_BUILD/build-htop"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --sysconfdir=/etc
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "htop"
    fi

    # --- Init System ---
    if ! skip_if_built "init"; then
    log "  -> MochiOS Init"
    
    # Copy init source to build directory
    local init_src="/scripts/../init"
    local init_bld="$MOCHI_BUILD/build-init"
    
    if [ -d "$init_src" ]; then
        rm -rf "$init_bld"
        cp -r "$init_src" "$init_bld"
        cd "$init_bld"
        
        # Build init
        eval make -j"$JOBS" $MAKE_CC
        
        # Install to /sbin/init
        install -D -m 755 build/init /sbin/init
        
        log "Init system installed to /sbin/init"
        mark_built "init"
    else
        log "Warning: Init source not found at $init_src, skipping"
    fi
    fi

    # --- System Utilities (powerctl) ---
    if ! skip_if_built "sysutils"; then
    log "  -> System Utilities"
    
    # Copy sysutils source to build directory
    local sysutils_src="/scripts/../sysutils"
    local sysutils_bld="$MOCHI_BUILD/build-sysutils"
    
    if [ -d "$sysutils_src" ]; then
        rm -rf "$sysutils_bld"
        cp -r "$sysutils_src" "$sysutils_bld"
        cd "$sysutils_bld"
        
        # Build sysutils
        eval make -j"$JOBS" $MAKE_CC
        
        # Install to /sbin
        install -D -m 755 powerctl/powerctl /sbin/powerctl
        ln -sf powerctl /sbin/poweroff
        ln -sf powerctl /sbin/reboot
        ln -sf powerctl /sbin/halt
        
        log "System utilities installed (powerctl, poweroff, reboot, halt)"
        mark_built "sysutils"
    else
        log "Warning: Sysutils source not found at $sysutils_src, skipping"
    fi
    fi

    log "System utilities installed"
}

# ---------------------------------------------------------------------------
# Step 4 – Linux Kernel
# ---------------------------------------------------------------------------
build_kernel() {
    skip_if_built "kernel" && return 0
    hdr "[4/5] Linux Kernel $LINUX_VER"
    local src="$MOCHI_SOURCES/linux-$LINUX_VER"
    require_src "$src"

    cd "$src"

    make mrproper

    # Use mochi.config if available, otherwise fall back to defconfig
    : "${MOCHI_KCONFIG:=/sources/mochi.config}"
    if [ -f "$MOCHI_KCONFIG" ]; then
        log "Using kernel config: $MOCHI_KCONFIG"
        cp "$MOCHI_KCONFIG" .config
        # Silently accept any new symbols introduced since the config was generated
        make olddefconfig
    else
        log "WARNING: $MOCHI_KCONFIG not found – falling back to defconfig"
        make defconfig
        make olddefconfig
    fi

    eval make -j"$JOBS" $KERNEL_CC bzImage modules

    # Install kernel modules
    make modules_install INSTALL_MOD_PATH=/

    # Install kernel image + support files to MochiOS boot directory
    mkdir -p "$BOOT_DIR"
    cp arch/x86_64/boot/bzImage  "$BOOT_DIR/vmlinuz"
    cp System.map                 "$BOOT_DIR/System.map"
    cp .config                    "$BOOT_DIR/config-$LINUX_VER"

    log "Kernel installed → $BOOT_DIR/vmlinuz"
    log "Modules installed → /lib/modules"
    mark_built "kernel"
}

# ---------------------------------------------------------------------------
# Step 5 – Linux Firmware
# ---------------------------------------------------------------------------
build_firmware() {
    skip_if_built "firmware" && return 0
    hdr "[5/6] Linux Firmware"
    
    local fw_src="$MOCHI_SOURCES/linux-firmware-20260309"
    local fw_dir="/System/Library/Kernel/Firmware"
    
    if [ ! -d "$fw_src" ]; then
        log "Warning: Linux firmware source not found at $fw_src"
        log "Make sure to run 'buildworld.sh fetch' first to extract firmware"
        return 0
    fi
    
    # Create firmware directory
    mkdir -p "$fw_dir"
    
    log "Installing all firmware from $fw_src..."
    log "This may take a few moments..."
    
    # Copy all firmware files and directories
    cp -r "$fw_src"/* "$fw_dir/"
    
    # Count installed files
    local fw_count=$(find "$fw_dir" -type f | wc -l)
    local fw_size=$(du -sh "$fw_dir" | cut -f1)
    
    log "Firmware installed to $fw_dir"
    log "  Files: $fw_count"
    log "  Size: $fw_size"
    mark_built "firmware"
}

# ---------------------------------------------------------------------------
# Step 6 – GRUB
# ---------------------------------------------------------------------------
build_grub() {
    hdr "[6/6] GRUB Bootloader (SKIPPED - optional)"
    log "  -> GRUB configuration (SKIPPED - bootloader can be configured manually)"
    return 0
    
    skip_if_built "grub" && return 0

    mkdir -p "$BOOT_DIR/grub"

    # Write grub.cfg
    cat > "$BOOT_DIR/grub/grub.cfg" << 'GRUBCFG'
set default=0
set timeout=5

insmod part_gpt
insmod fat
insmod ext2

menuentry "MochiOS" {
    search --no-floppy --set=root --label MOCHIOS_ROOT
    linux  /System/Library/Kernel/vmlinuz \
           root=LABEL=MOCHIOS_ROOT rw quiet splash
    initrd /System/Library/Kernel/initrd.img
}

menuentry "MochiOS (recovery mode)" {
    search --no-floppy --set=root --label MOCHIOS_ROOT
    linux  /System/Library/Kernel/vmlinuz \
           root=LABEL=MOCHIOS_ROOT rw init=/bin/bash
    initrd /System/Library/Kernel/initrd.img
}
GRUBCFG

    # Create a minimal /etc/default/grub
    mkdir -p /etc/default
    cat > /etc/default/grub << 'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="MochiOS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF

    log "GRUB config written → $BOOT_DIR/grub/grub.cfg"
    log "NOTE: grub-install is run by createimage.sh during image creation"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [STEP]

Steps (run in order, inside MochiOS chroot):
  bash       Build and install Bash
  coreutils  Build and install GNU Coreutils
  system     Build and install system utilities
               (ncurses, zlib, xz, gzip, tar, findutils,
                util-linux, inetutils, kmod, make, nano, htop,
                init, sysutils)
  kernel     Build and install Linux kernel + modules
  firmware   Install Linux firmware (i915, amdgpu, CPU microcode)
  grub       Write GRUB configuration
  all        Run all steps in order (default)

Environment:
  MOCHI_SOURCES  Extracted sources  (default: /sources)
  MOCHI_BUILD    Temp build dirs    (default: /build)
  JOBS           Parallel jobs      (default: nproc)
EOF
}

main() {
    setup_build_mode

    log "MochiOS Chroot Build"
    log "  Sources : $MOCHI_SOURCES"
    log "  Build   : $MOCHI_BUILD"
    log "  Boot    : $BOOT_DIR"
    log "  Jobs    : $JOBS"

    mkdir -p "$MOCHI_BUILD"

    local step="${1:-all}"
    case "$step" in
        bash)      build_bash ;;
        coreutils) build_coreutils ;;
        system)    build_system ;;
        kernel)    build_kernel ;;
        firmware)  build_firmware ;;
        grub)      build_grub ;;
        all)
            build_bash
            build_coreutils
            build_system
            build_kernel
            build_firmware
            build_grub
            ;;
        help|-h|--help) usage ;;
        *) usage; die "Unknown step: '$step'" ;;
    esac

    log "==> Chroot step '$step' complete"
}

main "$@"
