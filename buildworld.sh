#!/usr/bin/env bash
# MochiOS - Full System Build Orchestrator
#
# Build pipeline:
#   HOST  : headers → binutils → gcc(stage1) → glibc → gcc(stage2)
#   CHROOT: bash → coreutils → system → kernel → grub
#   IMAGE : GPT disk image (EFI + ext4 root)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration  (override via environment before calling this script)
# ---------------------------------------------------------------------------
: "${MOCHI_BUILD:=$PWD/buildfs}"
: "${MOCHI_SOURCES:=$MOCHI_BUILD/sources}"
: "${MOCHI_SYSROOT:=$MOCHI_BUILD/sysroot}"
: "${MOCHI_ROOTFS:=$MOCHI_BUILD/rootfs}"
: "${MOCHI_CROSS:=$MOCHI_BUILD/cross}"
: "${MOCHI_TARGET:=x86_64-mochios-linux-gnu}"
: "${MOCHI_IMAGE:=$MOCHI_BUILD/mochios.img}"
: "${JOBS:=$(nproc)}"

export MOCHI_BUILD MOCHI_SOURCES MOCHI_SYSROOT MOCHI_ROOTFS \
       MOCHI_CROSS MOCHI_TARGET MOCHI_IMAGE JOBS

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source URLs  (from SOURCES.txt)
# ---------------------------------------------------------------------------
SOURCES_LIST=(
    "https://git.kernel.org/torvalds/t/linux-7.0-rc5.tar.gz"
    "https://mirror.cyberbits.asia/gnu/glibc/glibc-2.43.tar.xz"
    "https://mirror.cyberbits.asia/gnu/gcc/gcc-15.2.0/gcc-15.2.0.tar.xz"
    "https://mirror.cyberbits.asia/gnu/binutils/binutils-2.46.0.tar.xz"
    "https://mirror.cyberbits.asia/gnu/make/make-4.4.tar.gz"
    "https://mirror.cyberbits.asia/gnu/bash/bash-5.3.tar.gz"
    "https://mirror.cyberbits.asia/gnu/coreutils/coreutils-9.10.tar.xz"
    "https://mirror.cyberbits.asia/gnu/findutils/findutils-4.10.0.tar.xz"
    "https://mirrors.edge.kernel.org/pub/linux/utils/util-linux/v2.40/util-linux-2.40.tar.gz"
    "https://mirror.cyberbits.asia/gnu/inetutils/inetutils-2.5.tar.xz"
    "https://mirror.cyberbits.asia/gnu/ncurses/ncurses-6.4.tar.gz"
    "https://zlib.net/zlib-1.3.2.tar.gz"
    "https://tukaani.org/xz/xz-5.8.2.tar.gz"
    "https://mirror.cyberbits.asia/gnu/gzip/gzip-1.14.tar.xz"
    "https://mirror.cyberbits.asia/gnu/tar/tar-1.35.tar.xz"
    "https://mirrors.edge.kernel.org/pub/linux/utils/kernel/kmod/kmod-34.tar.xz"
    "https://www.mpfr.org/mpfr-4.2.1/mpfr-4.2.1.tar.xz"
    "https://mirror.cyberbits.asia/gnu/mpc/mpc-1.3.1.tar.gz"
    "https://libisl.sourceforge.io/isl-0.27.tar.xz"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[BUILD] $(date '+%H:%M:%S')  $*"; }
die()  { echo "[BUILD] ERROR: $*" >&2; exit 1; }
hdr()  {
    echo
    echo "════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "════════════════════════════════════════════════════════════"
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "This command requires root (sudo)."
}

# ---------------------------------------------------------------------------
# Source fetch & extract
# ---------------------------------------------------------------------------
cmd_fetch() {
    hdr "Downloading Sources"
    mkdir -p "$MOCHI_SOURCES"

    for url in "${SOURCES_LIST[@]}"; do
        local archive
        archive="$(basename "$url")"
        local dest="$MOCHI_SOURCES/$archive"

        if [ -f "$dest" ]; then
            log "Already downloaded: $archive"
        else
            log "Fetching: $archive"
            if command -v wget >/dev/null 2>&1; then
                wget -q --show-progress -O "$dest" "$url"
            elif command -v curl >/dev/null 2>&1; then
                curl -L --progress-bar -o "$dest" "$url"
            else
                die "Neither wget nor curl found; install one to fetch sources."
            fi
        fi

        # Extract only if the directory does not yet exist
        local dirname="${archive%.tar.*}"
        dirname="${dirname%.gz}"   # handle .tar.gz → strip .tar later
        # Recompute properly:
        case "$archive" in
            *.tar.xz|*.tar.gz|*.tar.bz2)
                dirname="${archive}"
                dirname="${dirname%.tar.xz}"
                dirname="${dirname%.tar.gz}"
                dirname="${dirname%.tar.bz2}"
                ;;
        esac

        if [ ! -d "$MOCHI_SOURCES/$dirname" ]; then
            log "Extracting: $archive"
            case "$archive" in
                *.tar.xz)  tar -xJf "$dest" -C "$MOCHI_SOURCES" ;;
                *.tar.gz)  tar -xzf "$dest" -C "$MOCHI_SOURCES" ;;
                *.tar.bz2) tar -xjf "$dest" -C "$MOCHI_SOURCES" ;;
                *) die "Unknown archive format: $archive" ;;
            esac
        fi
    done

    log "==> All sources ready in $MOCHI_SOURCES"
}

# ---------------------------------------------------------------------------
# MochiOS Rootfs Directory Layout
# ---------------------------------------------------------------------------
cmd_rootfs() {
    hdr "Setting Up MochiOS Rootfs Layout"

    # Primary directory tree under /System/
    mkdir -p \
        "$MOCHI_ROOTFS/System/usr/bin" \
        "$MOCHI_ROOTFS/System/usr/sbin" \
        "$MOCHI_ROOTFS/System/usr/lib" \
        "$MOCHI_ROOTFS/System/usr/lib64" \
        "$MOCHI_ROOTFS/System/usr/include" \
        "$MOCHI_ROOTFS/System/usr/share/doc" \
        "$MOCHI_ROOTFS/System/usr/share/man" \
        "$MOCHI_ROOTFS/System/etc/default" \
        "$MOCHI_ROOTFS/System/Library/Kernel/grub" \
        "$MOCHI_ROOTFS/Applications" \
        "$MOCHI_ROOTFS/Library" \
        "$MOCHI_ROOTFS/Users/Administrator" \
        "$MOCHI_ROOTFS/Volumes" \
        "$MOCHI_ROOTFS/dev" \
        "$MOCHI_ROOTFS/proc" \
        "$MOCHI_ROOTFS/sys" \
        "$MOCHI_ROOTFS/run" \
        "$MOCHI_ROOTFS/tmp" \
        "$MOCHI_ROOTFS/var/lib/locate" \
        "$MOCHI_ROOTFS/var/lib/hwclock"

    # Internal System/ compat symlinks
    ln -sfn usr/lib   "$MOCHI_ROOTFS/System/lib"   2>/dev/null || true
    ln -sfn usr/lib64 "$MOCHI_ROOTFS/System/lib64" 2>/dev/null || true
    ln -sfn usr/bin   "$MOCHI_ROOTFS/System/bin"   2>/dev/null || true
    ln -sfn usr/sbin  "$MOCHI_ROOTFS/System/sbin"  2>/dev/null || true

    # Root-level symlinks (matching rootfs.txt)
    ln -sfn System/usr/bin        "$MOCHI_ROOTFS/bin"   2>/dev/null || true
    ln -sfn System/usr/sbin       "$MOCHI_ROOTFS/sbin"  2>/dev/null || true
    ln -sfn System/usr            "$MOCHI_ROOTFS/usr"   2>/dev/null || true
    ln -sfn System/lib            "$MOCHI_ROOTFS/lib"   2>/dev/null || true
    ln -sfn System/lib64          "$MOCHI_ROOTFS/lib64" 2>/dev/null || true
    ln -sfn System/etc            "$MOCHI_ROOTFS/etc"   2>/dev/null || true
    ln -sfn System/Library/Kernel "$MOCHI_ROOTFS/boot"  2>/dev/null || true
    ln -sfn Users/Administrator   "$MOCHI_ROOTFS/root"  2>/dev/null || true

    # Permissions
    chmod 1777 "$MOCHI_ROOTFS/tmp"
    chmod 0750 "$MOCHI_ROOTFS/Users/Administrator"

    log "==> Rootfs layout ready at $MOCHI_ROOTFS"
}

# ---------------------------------------------------------------------------
# HOST toolchain
# ---------------------------------------------------------------------------
cmd_host() {
    local step="${1:-all}"
    hdr "HOST Toolchain: $step"
    export PATH="$MOCHI_CROSS/bin:$PATH"
    bash "$SCRIPT_DIR/scripts/host/buildsource.sh" "$step"
}

# ---------------------------------------------------------------------------
# CHROOT utilities
# ---------------------------------------------------------------------------
_mount_chroot() {
    mount --bind /dev             "$MOCHI_ROOTFS/dev"
    mount -t devpts devpts        "$MOCHI_ROOTFS/dev/pts" -o gid=5,mode=0620
    mount -t proc   proc          "$MOCHI_ROOTFS/proc"
    mount -t sysfs  sysfs         "$MOCHI_ROOTFS/sys"
    mount -t tmpfs  tmpfs         "$MOCHI_ROOTFS/run"
    mount -t tmpfs  tmpfs         "$MOCHI_ROOTFS/tmp"
}

_umount_chroot() {
    umount -R "$MOCHI_ROOTFS/dev"     2>/dev/null || true
    umount    "$MOCHI_ROOTFS/proc"    2>/dev/null || true
    umount    "$MOCHI_ROOTFS/sys"     2>/dev/null || true
    umount    "$MOCHI_ROOTFS/run"     2>/dev/null || true
    umount    "$MOCHI_ROOTFS/tmp"     2>/dev/null || true
    umount    "$MOCHI_ROOTFS/sources" 2>/dev/null || true
    umount    "$MOCHI_ROOTFS/build"   2>/dev/null || true
}

_enter_chroot() {
    local step="$1"

    # Inject build scripts into rootfs
    mkdir -p "$MOCHI_ROOTFS/scripts/chroot"
    cp "$SCRIPT_DIR/scripts/chroot/buildsource.sh" \
       "$MOCHI_ROOTFS/scripts/chroot/buildsource.sh"
    chmod +x "$MOCHI_ROOTFS/scripts/chroot/buildsource.sh"

    # Bind-mount sources and build temp dir into chroot
    mkdir -p "$MOCHI_ROOTFS/sources" "$MOCHI_ROOTFS/build"
    mount --bind "$MOCHI_SOURCES"      "$MOCHI_ROOTFS/sources"
    mount --bind "$MOCHI_BUILD/build"  "$MOCHI_ROOTFS/build"  2>/dev/null || \
        mount -t tmpfs tmpfs "$MOCHI_ROOTFS/build"

    _mount_chroot

    local chroot_env=(
        HOME=/root
        TERM="${TERM:-xterm}"
        PS1='(mochios) \u:\w\$ '
        PATH=/usr/bin:/usr/sbin:/bin:/sbin
        MOCHI_SOURCES=/sources
        MOCHI_BUILD=/build
        JOBS="$JOBS"
    )

    chroot "$MOCHI_ROOTFS" \
        /usr/bin/env -i "${chroot_env[@]}" \
        /bin/bash /scripts/chroot/buildsource.sh "$step"

    _umount_chroot
}

cmd_chroot() {
    local step="${1:-all}"
    hdr "CHROOT Build: $step"
    require_root
    mkdir -p "$MOCHI_BUILD/build"
    _enter_chroot "$step"
}

# ---------------------------------------------------------------------------
# Shell (interactive chroot)
# ---------------------------------------------------------------------------
cmd_shell() {
    hdr "MochiOS Chroot Shell"
    require_root
    _mount_chroot
    mkdir -p "$MOCHI_ROOTFS/sources"
    mount --bind "$MOCHI_SOURCES" "$MOCHI_ROOTFS/sources"
    chroot "$MOCHI_ROOTFS" \
        /usr/bin/env -i \
        HOME=/root \
        TERM="${TERM:-xterm}" \
        PS1='(mochios-chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        /bin/bash --login
    _umount_chroot
}

# ---------------------------------------------------------------------------
# Disk image
# ---------------------------------------------------------------------------
cmd_image() {
    hdr "Creating Bootable Disk Image"
    require_root
    bash "$SCRIPT_DIR/scripts/host/createimage.sh"
}

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------
cmd_clean() {
    hdr "Clean Build Artifacts"
    log "This will remove all build dirs, cross toolchain, sysroot, and rootfs."
    log "Sources will NOT be deleted."
    read -rp "Confirm? [y/N] " ans
    [[ "$ans" == [yY] ]] || { log "Aborted."; exit 0; }
    rm -rf \
        "$MOCHI_BUILD"/build-* \
        "$MOCHI_BUILD/sysroot" \
        "$MOCHI_BUILD/cross" \
        "$MOCHI_BUILD/rootfs" \
        "$MOCHI_BUILD/build"
    log "==> Clean done (sources preserved at $MOCHI_SOURCES)"
}

cmd_distclean() {
    hdr "Full Distclean"
    log "This will remove EVERYTHING including downloaded sources."
    read -rp "Confirm? [y/N] " ans
    [[ "$ans" == [yY] ]] || { log "Aborted."; exit 0; }
    rm -rf "$MOCHI_BUILD"
    log "==> Distclean done"
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
MochiOS Build System
Usage: $0 [COMMAND] [STEP]

Commands:
  fetch            Download and extract all sources
  rootfs           Create MochiOS rootfs directory layout
  host [STEP]      Run host toolchain build
                     steps: headers | binutils | gcc1 | glibc | gcc2 | all
  chroot [STEP]    Run chroot build  (requires root)
                     steps: bash | coreutils | system | kernel | grub | all
  image            Create bootable GPT disk image  (requires root)
  shell            Enter interactive MochiOS chroot  (requires root)
  clean            Remove build artifacts (keeps sources)
  distclean        Remove everything including sources
  all              Full pipeline: fetch → rootfs → host → chroot → image

Environment variables:
  MOCHI_BUILD      Build root dir    (default: ./buildfs)
  MOCHI_TARGET     Cross triplet     (default: x86_64-mochios-linux-gnu)
  MOCHI_IMAGE      Output image path (default: \$MOCHI_BUILD/mochios.img)
  IMG_SIZE_MB      Disk image size   (default: 4096)
  EFI_SIZE_MB      EFI partition     (default: 512)
  JOBS             Parallel jobs     (default: nproc)

Examples:
  $0 all                   # Full build
  $0 host                  # Build entire host toolchain
  $0 host gcc1             # Build only GCC stage 1
  $0 chroot system         # Build only system utilities in chroot
  $0 image                 # Create disk image from existing rootfs
  JOBS=8 $0 host           # Use 8 parallel jobs

Build pipeline:
  HOST  : headers → binutils → gcc(stage1) → glibc → gcc(stage2)
  CHROOT: bash → coreutils → system → kernel → grub
  IMAGE : GPT (512MiB EFI + ext4 root)
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    local cmd="${1:-all}"
    local step="${2:-all}"

    log "MochiOS Build System"
    log "  Build root : $MOCHI_BUILD"
    log "  Target     : $MOCHI_TARGET"
    log "  Jobs       : $JOBS"

    case "$cmd" in
        fetch)        cmd_fetch ;;
        rootfs)       cmd_rootfs ;;
        host)         cmd_host "$step" ;;
        chroot)       cmd_chroot "$step" ;;
        image)        cmd_image ;;
        shell)        cmd_shell ;;
        clean)        cmd_clean ;;
        distclean)    cmd_distclean ;;
        all)
            cmd_fetch
            cmd_rootfs
            cmd_host all
            cmd_chroot all
            cmd_image
            ;;
        help|-h|--help) usage ;;
        *)  usage; die "Unknown command: '$cmd'" ;;
    esac

    log "==> Done"
}

main "$@"
