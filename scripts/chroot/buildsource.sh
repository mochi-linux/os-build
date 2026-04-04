#!/usr/bin/env bash
# MochiOS - Chroot Build Script
#
# Designed to run INSIDE the MochiOS chroot environment.
# Build order: Toolchain (Native) → Bash → Coreutils → System → Kernel

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
: "${MOCHI_SOURCES:=/sources}"
: "${MOCHI_BUILD:=/build}"
: "${JOBS:=$(nproc)}"
: "${BUILD_MODE:=host}"

# Package versions
LINUX_VER="7.0-rc5"
BINUTILS_VER="2.46.0"
GCC_VER="15.2.0"
ZSTD_VER="1.5.6"
GMP_VER="6.3.0"
MPFR_VER="4.2.1"
MPC_VER="1.3.1"
ISL_VER="0.27"
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
PYTHON_VER="3.14.3"
CMAKE_VER="4.3.1"
FASTFETCH_VER="2.61.0"
BTOP_VER="1.4.6"

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
            MAKE_CC="CC=\"icecc gcc\""
            CONFIGURE_CC="CC=\"icecc gcc\""
            KERNEL_CC="CC=\"icecc gcc\""
            ;;
        *)
            die "Unknown BUILD_MODE: $BUILD_MODE"
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

STATE_DIR="$MOCHI_BUILD/.buildstate"
mkdir -p "$STATE_DIR"

mark_built() {
    touch "$STATE_DIR/chroot-$1.done"
    log "✓ $1 build completed"
}

is_built() {
    [ -f "$STATE_DIR/chroot-$1.done" ]
}

skip_if_built() {
    if is_built "$1"; then
        log "⊳ Skipping $1 (already built)"
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
# Step 1 – Native Toolchain & Base Libraries
# ---------------------------------------------------------------------------
build_toolchain() {
    hdr "[1/6] Native Toolchain & Base Libraries"

    # --- GMP ---
    if ! skip_if_built "gmp"; then
    log "  -> GMP $GMP_VER"
    local src="$MOCHI_SOURCES/gmp-$GMP_VER"
    local bld="$MOCHI_BUILD/build-gmp"
    conf_build "$src" "$bld" --prefix=/usr --enable-cxx --disable-static
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "gmp"
    fi

    # --- MPFR ---
    if ! skip_if_built "mpfr"; then
    log "  -> MPFR $MPFR_VER"
    src="$MOCHI_SOURCES/mpfr-$MPFR_VER"
    bld="$MOCHI_BUILD/build-mpfr"
    conf_build "$src" "$bld" --prefix=/usr --disable-static
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "mpfr"
    fi

    # --- MPC ---
    if ! skip_if_built "mpc"; then
    log "  -> MPC $MPC_VER"
    src="$MOCHI_SOURCES/mpc-$MPC_VER"
    bld="$MOCHI_BUILD/build-mpc"
    conf_build "$src" "$bld" --prefix=/usr --disable-static
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "mpc"
    fi

    # --- ISL ---
    if ! skip_if_built "isl"; then
    log "  -> ISL $ISL_VER"
    src="$MOCHI_SOURCES/isl-$ISL_VER"
    bld="$MOCHI_BUILD/build-isl"
    conf_build "$src" "$bld" --prefix=/usr --disable-static
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "isl"
    fi

    # --- Ncurses ---
    if ! skip_if_built "ncurses"; then
    log "  -> Ncurses $NCURSES_VER"
    src="$MOCHI_SOURCES/ncurses-$NCURSES_VER"
    bld="$MOCHI_BUILD/build-ncurses"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --with-shared \
        --enable-widec \
        --without-debug \
        --enable-pc-files \
        --with-pkg-config-libdir=/usr/lib/pkgconfig
    eval make -j"$JOBS" $MAKE_CC
    make install
    for lib in ncurses form panel menu; do
        ln -sfn "lib${lib}w.so" "/usr/lib/lib${lib}.so"
    done
    ln -sfn libncursesw.so /usr/lib/libcurses.so
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

    # --- Zstd ---
    if ! skip_if_built "zstd"; then
    log "  -> Zstd $ZSTD_VER"
    src="$MOCHI_SOURCES/zstd-$ZSTD_VER"
    require_src "$src"
    cd "$src"
    eval make -j"$JOBS" $MAKE_CC
    make install PREFIX=/usr
    mark_built "zstd"
    fi

    # --- Binutils ---
    if ! skip_if_built "binutils"; then
    log "  -> Binutils $BINUTILS_VER"
    src="$MOCHI_SOURCES/binutils-$BINUTILS_VER"
    bld="$MOCHI_BUILD/build-binutils-native"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --with-sysroot=/ \
        --enable-gold \
        --enable-ld=default \
        --enable-plugins \
        --enable-shared \
        --disable-werror \
        --with-system-zlib \
        --with-zstd
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "binutils"
    fi

    # --- GCC ---
    if ! skip_if_built "gcc"; then
    log "  -> GCC $GCC_VER"
    src="$MOCHI_SOURCES/gcc-$GCC_VER"
    bld="$MOCHI_BUILD/build-gcc-native"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --with-sysroot=/ \
        --with-native-system-header-dir=/usr/include \
        --enable-languages=c,c++ \
        --enable-default-pie \
        --enable-default-ssp \
        --disable-multilib \
        --disable-bootstrap \
        --disable-nls \
        --with-system-zlib \
        --with-zstd
    eval make -j"$JOBS" $MAKE_CC
    make install
    ln -sfn gcc /usr/bin/cc
    mark_built "gcc"
    fi
}

# ---------------------------------------------------------------------------
# Step 2 – Bash
# ---------------------------------------------------------------------------
build_bash() {
    skip_if_built "bash" && return 0
    hdr "[2/6] Bash $BASH_VER"
    local src="$MOCHI_SOURCES/bash-$BASH_VER"
    local bld="$MOCHI_BUILD/build-bash"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --without-bash-malloc
    eval make -j"$JOBS" $MAKE_CC
    make install
    ln -sfn bash /usr/bin/sh
    mark_built "bash"
}

# ---------------------------------------------------------------------------
# Step 3 – Coreutils
# ---------------------------------------------------------------------------
build_coreutils() {
    skip_if_built "coreutils" && return 0
    hdr "[3/6] Coreutils $COREUTILS_VER"
    local src="$MOCHI_SOURCES/coreutils-$COREUTILS_VER"
    local bld="$MOCHI_BUILD/build-coreutils"
    FORCE_UNSAFE_CONFIGURE=1 \
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "coreutils"
}

# ---------------------------------------------------------------------------
# Step 4 – System Utilities
# ---------------------------------------------------------------------------
build_system() {
    hdr "[4/6] System Utilities"

    # XZ
    if ! skip_if_built "xz"; then
    log "  -> XZ $XZ_VER"
    local src="$MOCHI_SOURCES/xz-$XZ_VER"
    local bld="$MOCHI_BUILD/build-xz"
    conf_build "$src" "$bld" --prefix=/usr --disable-static
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "xz"
    fi

    # Gzip
    if ! skip_if_built "gzip"; then
    log "  -> Gzip $GZIP_VER"
    src="$MOCHI_SOURCES/gzip-$GZIP_VER"
    bld="$MOCHI_BUILD/build-gzip"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "gzip"
    fi

    # Tar
    if ! skip_if_built "tar"; then
    log "  -> Tar $TAR_VER"
    src="$MOCHI_SOURCES/tar-$TAR_VER"
    bld="$MOCHI_BUILD/build-tar"
    FORCE_UNSAFE_CONFIGURE=1 conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "tar"
    fi

    # Findutils
    if ! skip_if_built "findutils"; then
    log "  -> Findutils $FINDUTILS_VER"
    src="$MOCHI_SOURCES/findutils-$FINDUTILS_VER"
    bld="$MOCHI_BUILD/build-findutils"
    conf_build "$src" "$bld" --prefix=/usr --localstatedir=/var/lib/locate
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "findutils"
    fi

    # Util-linux
    if ! skip_if_built "util-linux"; then
    log "  -> Util-linux $UTIL_LINUX_VER"
    getent group root >/dev/null || groupadd -g 0 root
    getent passwd root >/dev/null || useradd -u 0 -g 0 -d /root -s /bin/bash root
    getent group tty >/dev/null || groupadd -g 5 tty
    src="$MOCHI_SOURCES/util-linux-$UTIL_LINUX_VER"
    bld="$MOCHI_BUILD/build-util-linux"
    conf_build "$src" "$bld" \
        --prefix=/usr \
        --disable-chfn-chsh \
        --disable-login \
        --disable-su \
        --without-python
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "util-linux"
    fi

    # Inetutils
    if ! skip_if_built "inetutils"; then
    log "  -> Inetutils $INETUTILS_VER"
    src="$MOCHI_SOURCES/inetutils-$INETUTILS_VER"
    bld="$MOCHI_BUILD/build-inetutils"
    conf_build "$src" "$bld" --prefix=/usr --disable-servers
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "inetutils"
    fi

    # Perl
    if ! skip_if_built "perl"; then
    log "  -> Perl $PERL_VER"
    src="$MOCHI_SOURCES/perl-$PERL_VER"
    cd "$src"
    [ -f Makefile ] && make distclean || true
    ./Configure -des -Dprefix=/usr -Duseshrplib -Dusethreads
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "perl"
    fi

    # Autoconf/Automake/Libtool
    for tool in autoconf:$AUTOCONF_VER automake:$AUTOMAKE_VER libtool:$LIBTOOL_VER; do
        local name="${tool%%:*}"
        local ver="${tool##*:}"
        if ! skip_if_built "$name"; then
            log "  -> $name $ver"
            src="$MOCHI_SOURCES/$name-$ver"
            bld="$MOCHI_BUILD/build-$name"
            conf_build "$src" "$bld" --prefix=/usr
            eval make -j"$JOBS" $MAKE_CC
            make install
            mark_built "$name"
        fi
    done

    # OpenSSL
    if ! skip_if_built "openssl"; then
    log "  -> OpenSSL $OPENSSL_VER"
    src="$MOCHI_SOURCES/openssl-$OPENSSL_VER"
    cd "$src"
    [ -f Makefile ] && make distclean || true
    ./Configure linux-x86_64 --prefix=/usr --openssldir=/etc/ssl shared zlib-dynamic
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "openssl"
    fi

    # Bison/Flex
    if ! skip_if_built "bison"; then
    log "  -> Bison $BISON_VER"
    src="$MOCHI_SOURCES/bison-$BISON_VER"
    bld="$MOCHI_BUILD/build-bison"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "bison"
    fi
    if ! skip_if_built "flex"; then
    log "  -> Flex $FLEX_VER"
    src="$MOCHI_SOURCES/flex-$FLEX_VER"
    bld="$MOCHI_BUILD/build-flex"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "flex"
    fi

    # Elfutils
    if ! skip_if_built "elfutils"; then
    log "  -> Elfutils $ELFUTILS_VER"
    src="$MOCHI_SOURCES/elfutils-$ELFUTILS_VER"
    bld="$MOCHI_BUILD/build-elfutils"
    conf_build "$src" "$bld" --prefix=/usr --disable-debuginfod
    eval make -j"$JOBS" $MAKE_CC CFLAGS="-g -O2 -Wno-error"
    make install
    mark_built "elfutils"
    fi

    # Make
    if ! skip_if_built "make"; then
    log "  -> Make $MAKE_VER"
    src="$MOCHI_SOURCES/make-$MAKE_VER"
    bld="$MOCHI_BUILD/build-make"
    conf_build "$src" "$bld" --prefix=/usr --without-guile
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "make"
    fi

    # Nano/Htop
    if ! skip_if_built "nano"; then
    log "  -> Nano $NANO_VER"
    src="$MOCHI_SOURCES/nano-$NANO_VER"
    bld="$MOCHI_BUILD/build-nano"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "nano"
    fi
    if ! skip_if_built "htop"; then
    log "  -> Htop $HTOP_VER"
    src="$MOCHI_SOURCES/htop-$HTOP_VER"
    bld="$MOCHI_BUILD/build-htop"
    conf_build "$src" "$bld" --prefix=/usr
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "htop"
    fi

    # CMake/Fastfetch/Btop
    if ! skip_if_built "cmake"; then
    log "  -> CMake $CMAKE_VER"
    src="$MOCHI_SOURCES/cmake-$CMAKE_VER"
    bld="$MOCHI_BUILD/build-cmake"
    mkdir -p "$bld" && cd "$bld"
    "$src/bootstrap" --prefix=/usr --parallel="$JOBS" -- -DBUILD_CursesDialog=OFF
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "cmake"
    fi
    if ! skip_if_built "fastfetch"; then
    log "  -> Fastfetch $FASTFETCH_VER"
    src="$MOCHI_SOURCES/fastfetch-$FASTFETCH_VER"
    bld="$MOCHI_BUILD/build-fastfetch"
    mkdir -p "$bld" && cd "$bld"
    cmake "$src" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
    eval make -j"$JOBS"
    make install
    mark_built "fastfetch"
    fi
    if ! skip_if_built "btop"; then
    log "  -> Btop $BTOP_VER"
    src="$MOCHI_SOURCES/btop-$BTOP_VER"
    cd "$src"
    eval make -j"$JOBS" $MAKE_CC PREFIX=/usr
    make install PREFIX=/usr
    mark_built "btop"
    fi

    # Python
    if ! skip_if_built "python"; then
    log "  -> Python $PYTHON_VER"
    src="$MOCHI_SOURCES/Python-$PYTHON_VER"
    bld="$MOCHI_BUILD/build-python"
    conf_build "$src" "$bld" --prefix=/usr --enable-shared --without-ensurepip
    eval make -j"$JOBS" $MAKE_CC
    make install
    mark_built "python"
    fi

    # Init & Sysutils
    if ! skip_if_built "init"; then
        if [ -d "/init" ]; then
            cd "/init"
            eval make -j"$JOBS" $MAKE_CC
            install -D -m 755 build/init /sbin/init
            mark_built "init"
        fi
    fi
    if ! skip_if_built "sysutils"; then
        if [ -d "/sysutils" ]; then
            cd "/sysutils"
            eval make -j"$JOBS" $MAKE_CC
            install -D -m 755 powerctl/powerctl /sbin/powerctl
            ln -sf powerctl /sbin/poweroff
            ln -sf powerctl /sbin/reboot
            ln -sf powerctl /sbin/halt
            install -D -m 755 launcher/launcher /usr/bin/launcher
            install -D -m 755 launcher/mkappbundle /usr/bin/mkappbundle
            mark_built "sysutils"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Step 5 – Kernel
# ---------------------------------------------------------------------------
build_kernel() {
    skip_if_built "kernel" && return 0
    hdr "[5/6] Linux Kernel $LINUX_VER"
    local src="$MOCHI_SOURCES/linux-$LINUX_VER"
    require_src "$src"
    cd "$src"
    make mrproper
    if [ -f "/sources/mochi.config" ]; then
        cp "/sources/mochi.config" .config
        make olddefconfig
    else
        make defconfig
    fi
    eval make -j"$JOBS" $KERNEL_CC bzImage modules
    make modules_install INSTALL_MOD_PATH=/
    mkdir -p "$BOOT_DIR"
    cp arch/x86_64/boot/bzImage "$BOOT_DIR/vmlinuz"
    mark_built "kernel"
}

# ---------------------------------------------------------------------------
# Step 6 – Firmware
# ---------------------------------------------------------------------------
build_firmware() {
    skip_if_built "firmware" && return 0
    hdr "[6/6] Linux Firmware"
    local fw_src="$MOCHI_SOURCES/linux-firmware-20260309"
    local fw_dir="/System/Library/Kernel/Firmware"
    if [ -d "$fw_src" ]; then
        mkdir -p "$fw_dir"
        cp -r "$fw_src"/* "$fw_dir/"
        mark_built "firmware"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [STEP]

Steps:
  toolchain  Build native GCC, Binutils, GMP, MPFR, MPC, ISL, Ncurses, Zlib
  bash       Build Bash
  coreutils  Build Coreutils
  system     Build system utilities (XZ, Gzip, Tar, Perl, etc.)
  kernel     Build Linux kernel
  firmware   Install firmware
  all        Run all steps in order (default)
EOF
}

main() {
    setup_build_mode
    log "MochiOS Chroot Build Started"
    mkdir -p "$MOCHI_BUILD"

    local step="${1:-all}"
    case "$step" in
        toolchain) build_toolchain ;;
        bash)      build_bash ;;
        coreutils) build_coreutils ;;
        system)    build_system ;;
        kernel)    build_kernel ;;
        firmware)  build_firmware ;;
        all)
            build_toolchain
            build_bash
            build_coreutils
            build_system
            build_kernel
            build_firmware
            ;;
        help|-h|--help) usage ;;
        *) usage; die "Unknown step: '$step'" ;;
    esac
    log "==> Chroot step '$step' complete"
}

main "$@"
