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
LINUX_VER="7.0-rc6"
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
}

# ---------------------------------------------------------------------------
# Step 2 – Coreutils
# ---------------------------------------------------------------------------
build_coreutils() {
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
}

# ---------------------------------------------------------------------------
# Step 3 – System Utilities
#   ncurses → zlib → xz → gzip → tar → findutils →
#   util-linux → inetutils → perl → autoconf → kmod → make
# ---------------------------------------------------------------------------
build_system() {
    hdr "[3/5] System Utilities"

    # --- Ncurses ---
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

    # --- Zlib ---
    log "  -> Zlib $ZLIB_VER"
    src="$MOCHI_SOURCES/zlib-$ZLIB_VER"
    bld="$MOCHI_BUILD/build-zlib"
    require_src "$src"
    rm -rf "$bld" && mkdir -p "$bld"
    cd "$bld"
    eval "$CONFIGURE_CC" "$src/configure" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- XZ Utils ---
    log "  -> XZ Utils $XZ_VER"
    src="$MOCHI_SOURCES/xz-$XZ_VER"
    bld="$MOCHI_BUILD/build-xz"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --disable-static \
        --docdir=/usr/share/doc/xz
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Gzip ---
    log "  -> Gzip $GZIP_VER"
    src="$MOCHI_SOURCES/gzip-$GZIP_VER"
    bld="$MOCHI_BUILD/build-gzip"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Tar ---
    log "  -> Tar $TAR_VER"
    src="$MOCHI_SOURCES/tar-$TAR_VER"
    bld="$MOCHI_BUILD/build-tar"
    FORCE_UNSAFE_CONFIGURE=1 \
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --bindir=/usr/bin
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Findutils ---
    log "  -> Findutils $FINDUTILS_VER"
    src="$MOCHI_SOURCES/findutils-$FINDUTILS_VER"
    bld="$MOCHI_BUILD/build-findutils"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --localstatedir=/var/lib/locate \
        --docdir=/usr/share/doc/findutils
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Util-linux ---
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

    # --- Inetutils ---
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

    # --- Perl ---
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

    # --- Autoconf ---
    log "  -> Autoconf $AUTOCONF_VER"
    src="$MOCHI_SOURCES/autoconf-$AUTOCONF_VER"
    bld="$MOCHI_BUILD/build-autoconf"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Automake ---
    log "  -> Automake $AUTOMAKE_VER"
    src="$MOCHI_SOURCES/automake-$AUTOMAKE_VER"
    bld="$MOCHI_BUILD/build-automake"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Libtool ---
    log "  -> Libtool $LIBTOOL_VER"
    src="$MOCHI_SOURCES/libtool-$LIBTOOL_VER"
    bld="$MOCHI_BUILD/build-libtool"
    conf_build "$src" "$bld" \
        --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install

    # --- Kmod ---
    log "  -> Kmod $KMOD_VER"
    src="$MOCHI_SOURCES/kmod-$KMOD_VER"
    bld="$MOCHI_BUILD/build-kmod"
    
    # Regenerate autotools files (requires autoconf built above)
    cd "$src"
    autoreconf -fiv
    
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --sysconfdir=/etc \
        --with-openssl \
        --with-xz \
        --with-zlib \
        --disable-manpages
    eval make -j"$JOBS" $MAKE_CC
    make install
    for prog in depmod insmod modinfo modprobe rmmod; do
        ln -sfn ../bin/kmod "/usr/sbin/$prog" 2>/dev/null || true
    done
    ln -sfn kmod /usr/bin/lsmod 2>/dev/null || true

    # --- Make ---
    log "  -> Make $MAKE_VER"
    src="$MOCHI_SOURCES/make-$MAKE_VER"
    bld="$MOCHI_BUILD/build-make"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --without-guile \
        --docdir=/usr/share/doc/make
    eval make -j"$JOBS" $MAKE_CC
    make install

    log "System utilities installed"
}

# ---------------------------------------------------------------------------
# Step 4 – Linux Kernel
# ---------------------------------------------------------------------------
build_kernel() {
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
}

# ---------------------------------------------------------------------------
# Step 5 – GRUB
# ---------------------------------------------------------------------------
build_grub() {
    hdr "[5/5] GRUB Bootloader"

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
                util-linux, inetutils, kmod, make)
  kernel     Build and install Linux kernel + modules
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
        grub)      build_grub ;;
        all)
            build_bash
            build_coreutils
            build_system
            build_kernel
            build_grub
            ;;
        help|-h|--help) usage ;;
        *) usage; die "Unknown step: '$step'" ;;
    esac

    log "==> Chroot step '$step' complete"
}

main "$@"
