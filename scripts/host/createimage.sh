#!/usr/bin/env bash
# MochiOS - Bootable Disk Image Creator
# Produces a GPT disk image: EFI System Partition + ext4 root partition

set -euo pipefail

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------
: "${MOCHI_BUILD:=$PWD/buildfs}"
: "${MOCHI_ROOTFS:=$MOCHI_BUILD/rootfs}"
: "${MOCHI_IMAGE:=$MOCHI_BUILD/mochios.img}"
: "${IMG_SIZE_MB:=4096}"
: "${EFI_SIZE_MB:=512}"

MNT_ROOT="/mnt/mochi-root"
MNT_EFI="/mnt/mochi-efi"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log() { echo "[IMAGE] $(date '+%H:%M:%S')  $*"; }
die() { echo "[IMAGE] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Must run as root"

for tool in parted mkfs.fat mkfs.ext4 losetup rsync grub-install; do
    command -v "$tool" >/dev/null 2>&1 || die "Required tool not found: $tool"
done

LOOP=""

cleanup() {
    log "Cleanup ..."
    umount "$MNT_EFI"  2>/dev/null || true
    umount "$MNT_ROOT" 2>/dev/null || true
    [ -n "$LOOP" ] && losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Create blank image
# ---------------------------------------------------------------------------
log "Creating disk image: $MOCHI_IMAGE  (${IMG_SIZE_MB} MiB)"
dd if=/dev/zero of="$MOCHI_IMAGE" bs=1M count="$IMG_SIZE_MB" status=progress

# ---------------------------------------------------------------------------
# Partition layout: GPT
#   p1 – EFI System Partition  (FAT32,  EFI_SIZE_MB)
#   p2 – Root partition         (ext4,   rest)
# ---------------------------------------------------------------------------
log "Partitioning image ..."
parted -s "$MOCHI_IMAGE" \
    mklabel gpt \
    mkpart ESP fat32  1MiB "${EFI_SIZE_MB}MiB" \
    set 1 esp on \
    mkpart root ext4  "${EFI_SIZE_MB}MiB" 100%

# ---------------------------------------------------------------------------
# Attach loop device
# ---------------------------------------------------------------------------
LOOP="$(losetup --find --show --partscan "$MOCHI_IMAGE")"
log "Loop device: $LOOP"

# Give the kernel a moment to register partition devices
sleep 1

# ---------------------------------------------------------------------------
# Format partitions
# ---------------------------------------------------------------------------
log "Formatting partitions ..."
mkfs.fat  -F 32 -n "MOCHIOS_EFI"  "${LOOP}p1"
mkfs.ext4 -L    "MOCHIOS_ROOT"    "${LOOP}p2"

# ---------------------------------------------------------------------------
# Mount and populate
# ---------------------------------------------------------------------------
mkdir -p "$MNT_ROOT" "$MNT_EFI"

mount "${LOOP}p2" "$MNT_ROOT"
mkdir -p "$MNT_ROOT/System/Library/Kernel"
mount "${LOOP}p1" "$MNT_EFI"

log "Copying rootfs → image (this may take a while) ..."
rsync -aHAX \
    --exclude='/dev/*' \
    --exclude='/proc/*' \
    --exclude='/sys/*' \
    --exclude='/run/*' \
    --exclude='/tmp/*' \
    --exclude='/sources' \
    --exclude='/build' \
    "$MOCHI_ROOTFS/" "$MNT_ROOT/"

# ---------------------------------------------------------------------------
# Generate initramfs
# ---------------------------------------------------------------------------
if command -v mkinitcpio >/dev/null 2>&1; then
    log "Generating initramfs with mkinitcpio ..."
    mkinitcpio -k "$MNT_ROOT/System/Library/Kernel/vmlinuz" \
               -g "$MNT_ROOT/System/Library/Kernel/initrd.img"
elif command -v dracut >/dev/null 2>&1; then
    log "Generating initramfs with dracut ..."
    dracut --force \
        --kver "$(ls "$MNT_ROOT/lib/modules/" | tail -1)" \
        "$MNT_ROOT/System/Library/Kernel/initrd.img"
else
    log "WARNING: No initramfs generator found (mkinitcpio/dracut)."
    log "         Boot may require a pre-built initrd.img."
fi

# ---------------------------------------------------------------------------
# Install GRUB (EFI)
# ---------------------------------------------------------------------------
log "Installing GRUB (x86_64-efi) ..."
grub-install \
    --target=x86_64-efi \
    --efi-directory="$MNT_EFI" \
    --boot-directory="$MNT_ROOT/System/Library/Kernel" \
    --bootloader-id="MochiOS" \
    --removable \
    --no-nvram

# ---------------------------------------------------------------------------
# Write grub.cfg
# ---------------------------------------------------------------------------
mkdir -p "$MNT_ROOT/System/Library/Kernel/grub"
cat > "$MNT_ROOT/System/Library/Kernel/grub/grub.cfg" << 'GRUBCFG'
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

log "GRUB config written"

# ---------------------------------------------------------------------------
# Unmount cleanly (trap will also run but that's fine)
# ---------------------------------------------------------------------------
umount "$MNT_EFI"  || true
umount "$MNT_ROOT" || true
losetup -d "$LOOP" || true
LOOP=""
trap - EXIT

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "============================================================"
log "  Image ready : $MOCHI_IMAGE"
log "  Size        : ${IMG_SIZE_MB} MiB"
log "  EFI         : ${EFI_SIZE_MB} MiB (FAT32, label: MOCHIOS_EFI)"
log "  Root        : $((IMG_SIZE_MB - EFI_SIZE_MB)) MiB (ext4, label: MOCHIOS_ROOT)"
log ""
log "  Test with QEMU:"
log "    qemu-system-x86_64 \\"
log "      -m 2G \\"
log "      -bios /usr/share/ovmf/OVMF.fd \\"
log "      -drive file=$MOCHI_IMAGE,format=raw \\"
log "      -nographic"
log "============================================================"
