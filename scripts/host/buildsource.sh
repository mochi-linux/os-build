#!/usr/bin/env bash
# MochiOS - Host Cross-Toolchain Build Script
# Build order: headers → binutils → gcc(stage1) → glibc → gcc(stage2)

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment  (all can be overridden by caller / scripts/buildworld.sh)
# ---------------------------------------------------------------------------
: "${MOCHI_BUILD:=$PWD/buildfs}"
: "${MOCHI_SOURCES:=$MOCHI_BUILD/sources}"
: "${MOCHI_SYSROOT:=$MOCHI_BUILD/sysroot}"
: "${MOCHI_CROSS:=$MOCHI_BUILD/cross}"
: "${MOCHI_TARGET:=x86_64-mochios-linux-gnu}"
: "${JOBS:=$(($(nproc) * 4))}"
: "${BUILD_MODE:=host}"  # host or cluster

# Package versions (mirror SOURCES.txt)
LINUX_VER="7.0-rc5"
BINUTILS_VER="2.46.0"
GCC_VER="15.2.0"
GLIBC_VER="2.43"
ZSTD_VER="1.5.6"
GMP_VER="6.3.0"
MPFR_VER="4.2.1"
MPC_VER="1.3.1"
ISL_VER="0.27"

export PATH="$MOCHI_CROSS/bin:$PATH"

# ---------------------------------------------------------------------------
# Build Mode Configuration
# ---------------------------------------------------------------------------
setup_build_mode() {
    case "$BUILD_MODE" in
        host)
            log "Build mode: HOST (local build)"
            export CC="gcc"
            export CXX="g++"
            ;;
        cluster)
            if ! command -v icecc >/dev/null 2>&1; then
                die "icecc not found. Install icecc for cluster builds."
            fi
            log "Build mode: CLUSTER (icecc distributed build)"
            log "  icecc version: $(icecc --version 2>&1 | head -n1)"
            export CC="icecc gcc"
            export CXX="icecc g++"
            ;;
        *)
            die "Unknown BUILD_MODE: $BUILD_MODE (use 'host' or 'cluster')"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[HOST] $(date '+%H:%M:%S')  $*"; }
die() { echo "[HOST] ERROR: $*" >&2; exit 1; }
hdr() {
    echo
    echo "──────────────────────────────────────────────────────────"
    echo "  $*"
    echo "──────────────────────────────────────────────────────────"
}

require_src() {
    local path="$1"
    [ -d "$path" ] || die "Source directory not found: $path"
}

# Ensure kernel headers are installed in the sysroot; run build_headers if missing
ensure_headers() {
    if [ ! -f "$MOCHI_SYSROOT/usr/include/linux/version.h" ]; then
        log "Kernel headers not found in sysroot – running headers step first ..."
        build_headers
    else
        log "Kernel headers already present in sysroot, skipping."
    fi
}

# Link GCC prerequisite libraries into the GCC source tree
link_gcc_prereqs() {
    local gcc_src="$MOCHI_SOURCES/gcc-$GCC_VER"
    for pair in "gmp:gmp-$GMP_VER" "mpfr:mpfr-$MPFR_VER" "mpc:mpc-$MPC_VER" "isl:isl-$ISL_VER"; do
        local lname="${pair%%:*}"
        local dname="${pair##*:}"
        if [ ! -e "$gcc_src/$lname" ]; then
            require_src "$MOCHI_SOURCES/$dname"
            ln -sfn "$MOCHI_SOURCES/$dname" "$gcc_src/$lname"
            log "  linked $dname → gcc/$lname"
        fi
    done
}

# ---------------------------------------------------------------------------
# Step 1 – Linux Kernel Headers
# ---------------------------------------------------------------------------
build_headers() {
    hdr "[1/6] Linux Kernel Headers (linux-$LINUX_VER)"
    local src="$MOCHI_SOURCES/linux-$LINUX_VER"
    require_src "$src"

    make -C "$src" mrproper

    make -C "$src" headers_install \
        ARCH=x86_64 \
        INSTALL_HDR_PATH="$MOCHI_SYSROOT/usr"

    # Remove dot-files left by the install target
    find "$MOCHI_SYSROOT/usr/include" \( -name '.*' -o -name '.*.cmd' \) -delete

    log "Headers installed → $MOCHI_SYSROOT/usr/include"
}

# ---------------------------------------------------------------------------
# Step 2 – Zstd (host support for GCC)
# ---------------------------------------------------------------------------
build_zstd() {
    hdr "Zstd $ZSTD_VER"
    local src="$MOCHI_SOURCES/zstd-$ZSTD_VER"
    require_src "$src"

    cd "$src"
    make -j"$JOBS" PREFIX="$MOCHI_CROSS"
    make install PREFIX="$MOCHI_CROSS"
}

# ---------------------------------------------------------------------------
# Step 3 – Cross Binutils
# ---------------------------------------------------------------------------
build_binutils() {
    hdr "[3/6] Binutils $BINUTILS_VER"
    local src="$MOCHI_SOURCES/binutils-$BINUTILS_VER"
    local bld="$MOCHI_BUILD/build-binutils"
    require_src "$src"

    mkdir -p "$bld"
    cd "$bld"

    if [ ! -f "$bld/.configured" ]; then
        log "Configuring binutils (fresh) ..."

        "$src/configure" \
            --prefix="$MOCHI_CROSS" \
            --with-sysroot="$MOCHI_SYSROOT" \
            --target="$MOCHI_TARGET" \
            --disable-nls \
            --disable-werror \
            --enable-gprofng=no \
            --enable-new-dtags \
            --enable-default-hash-style=gnu

        touch "$bld/.configured"
    else
        log "Resuming binutils build (already configured, skipping configure) ..."
    fi

    make -j"$JOBS" CC="$CC" CXX="$CXX"
    make install

    log "Binutils installed → $MOCHI_CROSS"
}

# ---------------------------------------------------------------------------
# Step 3 – GCC Stage 1  (no libc, C + minimal C++ only)
# ---------------------------------------------------------------------------
build_gcc_stage1() {
    hdr "[4/6] GCC $GCC_VER – Stage 1 (cross, no libc)"
    local src="$MOCHI_SOURCES/gcc-$GCC_VER"
    local bld="$MOCHI_BUILD/build-gcc-stage1"
    require_src "$src"

    ensure_headers
    link_gcc_prereqs

    mkdir -p "$bld"
    cd "$bld"

    if [ ! -f "$bld/.configured" ]; then
        log "Configuring GCC stage 1 (fresh) ..."

        "$src/configure" \
            --prefix="$MOCHI_CROSS" \
            --with-sysroot="$MOCHI_SYSROOT" \
            --target="$MOCHI_TARGET" \
            --with-glibc-version="$GLIBC_VER" \
            --with-newlib \
            --without-headers \
            --enable-initfini-array \
            --disable-nls \
            --disable-shared \
            --disable-multilib \
            --disable-decimal-float \
            --disable-threads \
            --disable-libatomic \
            --disable-libgomp \
            --disable-libquadmath \
            --disable-libssp \
            --disable-libvtv \
            --disable-libstdcxx \
            --with-zstd="$MOCHI_CROSS" \
            --enable-languages=c,c++

        touch "$bld/.configured"
    else
        log "Resuming GCC stage 1 build (already configured, skipping configure) ..."
    fi

    make -j"$JOBS" CC="$CC" CXX="$CXX" all-gcc all-target-libgcc
    make install-gcc install-target-libgcc

    log "GCC Stage 1 installed → $MOCHI_CROSS"
}

# ---------------------------------------------------------------------------
# Step 4 – Glibc  (cross-compiled against stage-1 GCC)
# ---------------------------------------------------------------------------
build_glibc() {
    hdr "[5/6] Glibc $GLIBC_VER"
    local src="$MOCHI_SOURCES/glibc-$GLIBC_VER"
    local bld="$MOCHI_BUILD/build-glibc"
    require_src "$src"

    # x86_64 needs lib64 → lib in the sysroot
    [ -e "$MOCHI_SYSROOT/usr/lib64" ] || \
        ln -sfn lib "$MOCHI_SYSROOT/usr/lib64"

    mkdir -p "$bld"
    cd "$bld"

    if [ ! -f "$bld/.configured" ]; then
        log "Configuring glibc (fresh) ..."

        # Detect the build machine's triplet
        local build_triplet
        build_triplet="$(gcc -dumpmachine 2>/dev/null || echo x86_64-pc-linux-gnu)"

        "$src/configure" \
            --prefix=/usr \
            --host="$MOCHI_TARGET" \
            --build="$build_triplet" \
            --enable-kernel=5.15 \
            --with-headers="$MOCHI_SYSROOT/usr/include" \
            --disable-nscd \
            --disable-werror \
            libc_cv_slibdir=/usr/lib

        touch "$bld/.configured"
    else
        log "Resuming glibc build (already configured, skipping configure) ..."
    fi

    make -j"$JOBS" CC="$CC" CXX="$CXX"
    make DESTDIR="$MOCHI_SYSROOT" install

    # Fix ldd hardcoded /usr prefix
    sed '/RTLDLIST=/s@/usr@@g' -i "$MOCHI_SYSROOT/usr/bin/ldd"

    log "Glibc installed → $MOCHI_SYSROOT"
}

# ---------------------------------------------------------------------------
# Step 5 – GCC Stage 2  (full cross compiler with glibc support)
# ---------------------------------------------------------------------------
build_gcc_stage2() {
    hdr "[6/6] GCC $GCC_VER – Stage 2 (full cross compiler)"
    local src="$MOCHI_SOURCES/gcc-$GCC_VER"
    local bld="$MOCHI_BUILD/build-gcc-stage2"
    require_src "$src"

    ensure_headers
    link_gcc_prereqs

    mkdir -p "$bld"
    cd "$bld"

    if [ ! -f "$bld/.configured" ]; then
        log "Configuring GCC stage 2 (fresh) ..."

        "$src/configure" \
            --prefix="$MOCHI_CROSS" \
            --with-sysroot="$MOCHI_SYSROOT" \
            --with-build-sysroot="$MOCHI_SYSROOT" \
            --target="$MOCHI_TARGET" \
            --enable-initfini-array \
            --disable-nls \
            --enable-shared \
            --disable-multilib \
            --enable-languages=c,c++ \
            --enable-default-pie \
            --enable-default-ssp \
            --enable-host-pie \
            --disable-libstdcxx-pch \
            --disable-libsanitizer \
            --disable-libgomp \
            --disable-libquadmath \
            --disable-libatomic \
            --with-zstd="$MOCHI_CROSS" \
            ac_cv_sys_file_offset_bits=no

        touch "$bld/.configured"
    else
        log "Resuming GCC stage 2 build (already configured, skipping configure) ..."
    fi

    make -j"$JOBS" CC="$CC" CXX="$CXX"
    make install

    # Install target libraries (libstdc++, libgcc, etc.) to sysroot
    mkdir -p "$MOCHI_SYSROOT/usr/lib"
    if [ -d "$MOCHI_CROSS/$MOCHI_TARGET/lib64" ]; then
        cp -a "$MOCHI_CROSS/$MOCHI_TARGET/lib64/"* "$MOCHI_SYSROOT/usr/lib/"
    elif [ -d "$MOCHI_CROSS/$MOCHI_TARGET/lib" ]; then
        cp -a "$MOCHI_CROSS/$MOCHI_TARGET/lib/"* "$MOCHI_SYSROOT/usr/lib/"
    fi

    log "GCC Stage 2 installed → $MOCHI_CROSS"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [STEP]

Steps (run in order):
  headers    Install Linux kernel headers to sysroot
  zstd       Build zstd (host library for GCC)
  binutils   Build cross binutils
  gcc1       Build GCC stage 1 (no libc)
  glibc      Build glibc against stage-1 GCC
  gcc2       Build GCC stage 2 (full cross compiler)
  all        Run all steps in order (default)

Environment:
  MOCHI_BUILD    Build root          (default: ./buildfs)
  MOCHI_SOURCES  Extracted sources   (default: \$MOCHI_BUILD/sources)
  MOCHI_SYSROOT  Cross sysroot       (default: \$MOCHI_BUILD/sysroot)
  MOCHI_CROSS    Cross tools prefix  (default: \$MOCHI_BUILD/cross)
  MOCHI_TARGET   Target triplet      (default: x86_64-mochios-linux-gnu)
  JOBS           Parallel jobs       (default: nproc)
EOF
}

main() {
    setup_build_mode

    log "MochiOS Host Toolchain Build"
    log "  Target  : $MOCHI_TARGET"
    log "  Cross   : $MOCHI_CROSS"
    log "  Sysroot : $MOCHI_SYSROOT"
    log "  Sources : $MOCHI_SOURCES"
    log "  Jobs    : $JOBS"

    mkdir -p \
        "$MOCHI_CROSS" \
        "$MOCHI_SYSROOT/usr/include" \
        "$MOCHI_SYSROOT/usr/lib"

    local step="${1:-all}"
    case "$step" in
        headers)  build_headers ;;
        zstd)     build_zstd ;;
        binutils) build_binutils ;;
        gcc1)     ensure_headers; build_gcc_stage1 ;;
        glibc)    build_glibc ;;
        gcc2)     ensure_headers; build_gcc_stage2 ;;
        all)
            build_headers
            build_zstd
            build_binutils
            build_gcc_stage1
            build_glibc
            build_gcc_stage2
            ;;
        help|-h|--help) usage ;;
        *) usage; die "Unknown step: '$step'" ;;
    esac

    log "==> Host toolchain step '$step' complete"
}

main "$@"
