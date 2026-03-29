#!/usr/bin/env bash
# MochiOS – Rootfs Bootstrap Populate
#
# Cross-compiles bash + coreutils into MOCHI_ROOTFS and copies
# glibc shared libraries from MOCHI_SYSROOT so the chroot is
# enterable for the second-phase build.
#
# Runs on the HOST after cmd_host (cross-toolchain) completes.

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
: "${MOCHI_BUILD:=$PWD/buildfs}"
: "${MOCHI_SOURCES:=$MOCHI_BUILD/sources}"
: "${MOCHI_SYSROOT:=$MOCHI_BUILD/sysroot}"
: "${MOCHI_ROOTFS:=$MOCHI_BUILD/rootfs}"
: "${MOCHI_CROSS:=$MOCHI_BUILD/cross}"
: "${MOCHI_TARGET:=x86_64-mochios-linux-gnu}"
: "${JOBS:=$(nproc)}"

BASH_VER="5.3"
COREUTILS_VER="9.10"

export PATH="$MOCHI_CROSS/bin:$PATH"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[POPULATE] $(date '+%H:%M:%S')  $*"; }
die() { echo "[POPULATE] ERROR: $*" >&2; exit 1; }
hdr() {
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "════════════════════════════════════════════════════════════"
}

# ---------------------------------------------------------------------------
# Step 0 – Copy kernel + glibc headers from sysroot into rootfs
# ---------------------------------------------------------------------------
populate_headers() {
    hdr "[0/3] Copying sysroot headers to rootfs"

    local src_inc="$MOCHI_SYSROOT/usr/include"
    local dst_inc="$MOCHI_ROOTFS/System/usr/include"
    mkdir -p "$dst_inc"

    [ -d "$src_inc" ] || die "Sysroot has no include dir: $src_inc"

    # Copy kernel and glibc headers verbatim
    cp -a "$src_inc/" "$dst_inc/" 2>/dev/null || \
        rsync -a "$src_inc/" "$dst_inc/"

    log "Headers installed → $dst_inc"
}

# ---------------------------------------------------------------------------
# Step 1 – Copy glibc from sysroot into rootfs
# ---------------------------------------------------------------------------
populate_glibc() {
    hdr "[1/3] Copying glibc libraries to rootfs"

    local rootlib="$MOCHI_ROOTFS/System/usr/lib"
    mkdir -p "$rootlib"

    # Copy all shared libraries and symlinks from the sysroot
    cp -a "$MOCHI_SYSROOT/usr/lib/"*.so*       "$rootlib/" 2>/dev/null || true
    cp -a "$MOCHI_SYSROOT/usr/lib/"*.a          "$rootlib/" 2>/dev/null || true

    # glibc also installs to /usr/lib/gconv/, /usr/lib/audit/, etc.
    for subdir in gconv audit; do
        [ -d "$MOCHI_SYSROOT/usr/lib/$subdir" ] && \
            cp -a "$MOCHI_SYSROOT/usr/lib/$subdir" "$rootlib/" 2>/dev/null || true
    done

    # Ensure lib64 → lib symlink so ELF interpreter /lib64/ld-linux-x86-64.so.2 resolves
    if [ ! -L "$MOCHI_ROOTFS/System/usr/lib64" ]; then
        rm -rf "$MOCHI_ROOTFS/System/usr/lib64"
        ln -sfn lib "$MOCHI_ROOTFS/System/usr/lib64"
        log "Created System/usr/lib64 → lib"
    fi

    log "Glibc libraries installed → $rootlib"
}

# ---------------------------------------------------------------------------
# Step 2 – Cross-compile bash into rootfs
# ---------------------------------------------------------------------------
populate_bash() {
    hdr "[2/3] Cross-compiling bash $BASH_VER → rootfs"

    local src="$MOCHI_SOURCES/bash-$BASH_VER"
    local bld="$MOCHI_BUILD/build-bash-bootstrap"
    [ -d "$src" ] || die "bash source not found: $src"

    if [ -f "$bld/.done" ]; then
        log "bash bootstrap already done – skipping."
        return
    fi

    rm -rf "$bld"; mkdir -p "$bld"; cd "$bld"

    "$src/configure" \
        --prefix=/usr \
        --host="$MOCHI_TARGET" \
        --build="$(gcc -dumpmachine 2>/dev/null || echo x86_64-pc-linux-gnu)" \
        --without-bash-malloc \
        --disable-nls \
        bash_cv_func_sigsetjmp=present \
        bash_cv_have_mbstate_t=yes \
        bash_cv_func_strcoll_works=yes \
        bash_cv_func_ctype_nonascii=yes \
        bash_cv_opendir_not_robust=no \
        bash_cv_func_snprintf=yes \
        bash_cv_func_vsnprintf=yes \
        bash_cv_must_reinstall_sighandlers=no \
        bash_cv_sys_named_pipes=present \
        bash_cv_func_printf_a_format=yes \
        bash_cv_job_control_missing=present \
        bash_cv_sys_siglist=yes \
        bash_cv_decl_under_sys_siglist=yes

    make -j"$JOBS"
    make DESTDIR="$MOCHI_ROOTFS" install

    # Provide /bin/sh → bash (followed through symlinks in rootfs layout)
    ln -sfn bash "$MOCHI_ROOTFS/usr/bin/sh" 2>/dev/null || true

    touch "$bld/.done"
    log "bash installed → rootfs/usr/bin/bash"
}

# ---------------------------------------------------------------------------
# Step 3 – Cross-compile coreutils into rootfs (provides /usr/bin/env, etc.)
# ---------------------------------------------------------------------------
populate_coreutils() {
    hdr "[3/3] Cross-compiling coreutils $COREUTILS_VER → rootfs"

    local src="$MOCHI_SOURCES/coreutils-$COREUTILS_VER"
    local bld="$MOCHI_BUILD/build-coreutils-bootstrap"
    [ -d "$src" ] || die "coreutils source not found: $src"

    if [ -f "$bld/.done" ]; then
        log "coreutils bootstrap already done – skipping."
        return
    fi

    rm -rf "$bld"; mkdir -p "$bld"; cd "$bld"

    "$src/configure" \
        --prefix=/usr \
        --host="$MOCHI_TARGET" \
        --build="$(gcc -dumpmachine 2>/dev/null || echo x86_64-pc-linux-gnu)" \
        --enable-install-program=hostname \
        --enable-no-install-program=kill,uptime \
        --disable-nls \
        fu_cv_sys_stat_statfs2_bsize=yes \
        gl_cv_func_working_mkstemp=yes \
        gl_cv_func_working_acl_get_file=no \
        ac_cv_func_getgroups=yes \
        ac_cv_func_getgroups_works=yes

    make -j"$JOBS"
    make DESTDIR="$MOCHI_ROOTFS" install

    touch "$bld/.done"
    log "coreutils installed → rootfs/usr/bin/{env,ls,cp,...}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
hdr "MochiOS Rootfs Bootstrap"
log "  Sysroot : $MOCHI_SYSROOT"
log "  Rootfs  : $MOCHI_ROOTFS"
log "  Cross   : $MOCHI_CROSS"
log "  Sources : $MOCHI_SOURCES"
log "  Jobs    : $JOBS"

[ -d "$MOCHI_SYSROOT/usr/lib" ] || die "Sysroot not found – run 'host' step first."
[ -d "$MOCHI_ROOTFS/System"   ] || die "Rootfs not found – run 'rootfs' step first."
[ -x "$MOCHI_CROSS/bin/$MOCHI_TARGET-gcc" ] || die "Cross-compiler not found – run 'host' step first."

populate_headers
populate_glibc
populate_bash
populate_coreutils

log ""
log "==> Rootfs bootstrap complete. Ready to enter chroot."
