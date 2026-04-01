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
    
    # Unmount image mounts first
    local image_mount="$MOCHI_BUILD/image-mount"
    if [ -d "$image_mount" ]; then
        log "Unmounting image mounts..."
        umount -l "$image_mount/boot/efi" 2>/dev/null || true
        umount -l "$image_mount" 2>/dev/null || true
        sleep 1
    fi
    
    # First pass: unmount all known mount points with lazy unmount
    log "Unmounting chroot system mounts..."
    umount -l "$MOCHI_ROOTFS/dev/pts"     2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/dev"         2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/proc"        2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/sys"         2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/run"         2>/dev/null || true
    umount -l "$MOCHI_ROOTFS/tmp"         2>/dev/null || true
    
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
    
    # Give kernel time to process lazy unmounts
    sleep 1
    
    # Second pass: find and unmount any remaining mounts under rootfs
    log "Checking for remaining mounts under $MOCHI_ROOTFS..."
    if command -v findmnt >/dev/null 2>&1; then
        local remaining
        remaining=$(findmnt -R -n -o TARGET "$MOCHI_ROOTFS" 2>/dev/null | tac || true)
        if [ -n "$remaining" ]; then
            log "Found remaining mounts, force unmounting..."
            while IFS= read -r mount_point; do
                if [ -n "$mount_point" ]; then
                    log "  Unmounting: $mount_point"
                    umount -l "$mount_point" 2>/dev/null || true
                fi
            done <<< "$remaining"
            sleep 1
        fi
    fi
    
    # Third pass: aggressive cleanup if anything still mounted
    if findmnt -R -n "$MOCHI_ROOTFS" >/dev/null 2>&1; then
        log "WARNING: Some mounts still present, attempting force unmount..."
        umount -l -R "$MOCHI_ROOTFS" 2>/dev/null || true
        sleep 1
    fi
    
    # Detach all loop devices
    log "Detaching loop devices..."
    for loop in /dev/loop*; do
        if [ -b "$loop" ] && losetup "$loop" 2>/dev/null | grep -q "$MOCHI_BUILD"; then
            log "  Detaching: $loop"
            losetup -d "$loop" 2>/dev/null || true
        fi
    done
    
    log "All bind mounts unmounted successfully"
    log ""
    log "Verifying with lsblk..."
    lsblk 2>/dev/null || true
    log ""
    log "Remaining mounts under $MOCHI_ROOTFS (if any):"
    findmnt -R "$MOCHI_ROOTFS" 2>/dev/null || log "  None - all clean!"
}

main() {
    require_root
    umount_all
    log "Done!"
}

main "$@"
