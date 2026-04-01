#!/usr/bin/env bash
# MochiOS - Unmount All Build Bind Mounts
# This script unmounts all bind mounts created during the build process

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${MOCHI_BUILD:=$SCRIPT_DIR/buildfs}"
: "${MOCHI_ROOTFS:=$MOCHI_BUILD/rootfs}"

log() { echo "[UMOUNT] $(date +%H:%M:%S)  $*"; }
hdr() { echo ""; echo "──────────────────────────────────────────────────────────"; echo "  $*"; echo "──────────────────────────────────────────────────────────"; }

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "ERROR: This script must be run as root (use sudo)"
        exit 1
    fi
}

umount_all() {
    hdr "Unmounting All MochiOS Build Bind Mounts"
    
    log "Rootfs path: $MOCHI_ROOTFS"
    
    # Unmount chroot system mounts (from _umount_chroot)
    log "Unmounting chroot system mounts..."
    umount -l "$MOCHI_ROOTFS/dev/pts"     2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/dev"         2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/proc"        2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/sys"         2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/run"         2>/dev/null || true
    
    # Unmount build directories
    log "Unmounting build directories..."
    umount -l "$MOCHI_ROOTFS/sources"     2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/build"       2>/dev/null || true
    
    # Unmount toolchain and host mounts
    log "Unmounting toolchain and host mounts..."
    umount -l "$MOCHI_ROOTFS/cross"       2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/host-bin"    2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/host-lib64"  2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/host-usrlib" 2>/dev/null || true
    
    # Double-check with findmnt and unmount any remaining mounts under rootfs
    log "Checking for remaining mounts under $MOCHI_ROOTFS..."
    if command -v findmnt >/dev/null 2>&1; then
        local remaining
        remaining=$(findmnt -R -n -o TARGET "$MOCHI_ROOTFS" 2>/dev/null | tac || true)
        if [ -n "$remaining" ]; then
            log "Found remaining mounts, unmounting..."
            while IFS= read -r mount_point; do
                [ -n "$mount_point" ] && umount -l "$mount_point" 2>/dev/null || true
            done <<< "$remaining"
        fi
    fi
    
    log "All bind mounts unmounted successfully"
    log ""
    log "Verifying with lsblk..."
    lsblk 2>/dev/null || true
}

main() {
    require_root
    umount_all
    log "Done!"
}

main "$@"
