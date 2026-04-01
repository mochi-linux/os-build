#!/usr/bin/env bash
# MochiOS - Distribution Tarball Creator
# Creates a clean read-only rootfs tarball for distribution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${MOCHI_BUILD:=$SCRIPT_DIR/buildfs}"
: "${MOCHI_ROOTFS:=$MOCHI_BUILD/rootfs}"
: "${DIST_DIR:=$SCRIPT_DIR/dist}"
: "${DIST_NAME:=mochios-rootfs}"
: "${DIST_VERSION:=$(date +%Y%m%d)}"
: "${IMAGE_SIZE:=1G}"
: "${IMAGE_NAME:=mochios-${DIST_VERSION}.img}"

log() { echo "[DIST] $(date +%H:%M:%S)  $*"; }
die() { echo "[DIST] ERROR: $*" >&2; exit 1; }
hdr() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  $*"
    echo "════════════════════════════════════════════════════════════"
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root (use sudo)"
    fi
}

copy_system_config() {
    hdr "Copying System Configuration"
    
    local config_src="$SCRIPT_DIR/config/etc"
    local config_dst="$MOCHI_ROOTFS/System/etc"
    
    if [ ! -d "$config_src" ]; then
        log "Warning: No config files found at $config_src"
        return 0
    fi
    
    log "Copying configuration files from $config_src to $config_dst"
    
    # Create etc directory if it doesn't exist
    mkdir -p "$config_dst"
    
    # Copy all config files
    cp -av "$config_src"/* "$config_dst/"
    
    # Set proper permissions
    chmod 644 "$config_dst"/{fstab,hostname,hosts,shells,issue,os-release,inittab,nsswitch.conf,profile} 2>/dev/null || true
    chmod 600 "$config_dst/shadow" 2>/dev/null || true
    chmod 644 "$config_dst"/{passwd,group} 2>/dev/null || true
    
    log "System configuration files installed"
}

create_dist_tarball() {
    hdr "MochiOS Distribution Builder"
    
    log "Rootfs path: $MOCHI_ROOTFS"
    log "Output directory: $DIST_DIR"
    log "Distribution name: $DIST_NAME-$DIST_VERSION"
    
    # Verify rootfs exists
    if [ ! -d "$MOCHI_ROOTFS" ]; then
        die "Rootfs not found at $MOCHI_ROOTFS. Run buildworld.sh first."
    fi
    
    # Copy system configuration files
    copy_system_config
    
    # Create dist directory
    mkdir -p "$DIST_DIR"
    
    # Define exclusion patterns for tar
    local exclude_patterns=(
        # Build artifacts
        --exclude='build'
        --exclude='sources'
        --exclude='.buildstate'
        
        # Host bind mounts
        --exclude='cross'
        --exclude='host-bin'
        --exclude='host-lib64'
        --exclude='host-usrlib'
        
        # Init source (already compiled to /sbin/init)
        --exclude='init'
        
        # Temporary directories (will be empty in tarball)
        --exclude='dev/*'
        --exclude='proc/*'
        --exclude='sys/*'
        --exclude='run/*'
        --exclude='tmp/*'
        
        # Build scripts (optional - remove if you want to keep them)
        --exclude='scripts'
        
        # Cache and logs
        --exclude='var/cache/*'
        --exclude='var/log/*'
        --exclude='var/tmp/*'
        
        # Lost+found
        --exclude='lost+found'
    )
    
    log "Creating distribution tarball..."
    log "  Excluding build artifacts and temporary files"
    
    # Create compressed tarball
    local tarball="$DIST_DIR/$DIST_NAME-$DIST_VERSION.tar.xz"
    
    tar -C "$MOCHI_ROOTFS" \
        "${exclude_patterns[@]}" \
        --numeric-owner \
        --create \
        --xz \
        --file="$tarball" \
        .
    
    # Create checksum
    log "Generating checksums..."
    (cd "$DIST_DIR" && sha256sum "$DIST_NAME-$DIST_VERSION.tar.xz" > "$DIST_NAME-$DIST_VERSION.tar.xz.sha256")
    
    # Get tarball size
    local size=$(du -h "$tarball" | cut -f1)
    
    hdr "Distribution Created Successfully"
    log ""
    log "Tarball: $tarball"
    log "Size: $size"
    log "Checksum: $DIST_DIR/$DIST_NAME-$DIST_VERSION.tar.xz.sha256"
    log ""
    log "To extract:"
    log "  sudo tar -xJf $tarball -C /path/to/destination"
    log ""
    log "To verify:"
    log "  cd $DIST_DIR && sha256sum -c $DIST_NAME-$DIST_VERSION.tar.xz.sha256"
}

create_manifest() {
    hdr "Creating Distribution Manifest"
    
    local manifest="$DIST_DIR/$DIST_NAME-$DIST_VERSION.manifest"
    
    cat > "$manifest" << EOF
MochiOS Distribution Manifest
==============================

Distribution: $DIST_NAME
Version: $DIST_VERSION
Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Build Host: $(hostname)

Contents:
---------
EOF
    
    # List major components
    log "Scanning rootfs contents..."
    
    if [ -f "$MOCHI_ROOTFS/System/Library/Kernel/vmlinuz" ]; then
        local kernel_ver=$(file "$MOCHI_ROOTFS/System/Library/Kernel/vmlinuz" | grep -oP 'version \K[^ ]+' || echo "unknown")
        echo "- Linux Kernel: $kernel_ver" >> "$manifest"
    fi
    
    if [ -x "$MOCHI_ROOTFS/bin/bash" ]; then
        local bash_ver=$("$MOCHI_ROOTFS/bin/bash" --version 2>/dev/null | head -n1 || echo "unknown")
        echo "- Bash: $bash_ver" >> "$manifest"
    fi
    
    if [ -x "$MOCHI_ROOTFS/usr/bin/gcc" ]; then
        echo "- GCC toolchain: installed" >> "$manifest"
    fi
    
    cat >> "$manifest" << EOF

Directory Structure:
--------------------
/System/usr/bin     - User binaries
/System/usr/sbin    - System binaries
/System/usr/lib     - Libraries
/System/Library     - System libraries and frameworks
/System/etc         - System configuration
/Users              - User home directories
/Applications       - Applications
/Library            - Application support

Excluded from tarball:
----------------------
- build/            Build artifacts
- sources/          Source code
- cross/            Cross-compilation toolchain
- host-bin/         Host system binaries (bind mounts)
- host-lib64/       Host system libraries (bind mounts)
- dev/*, proc/*, sys/*, run/*, tmp/*  (empty in tarball)

Installation:
-------------
1. Extract tarball to target location:
   sudo tar -xJf $DIST_NAME-$DIST_VERSION.tar.xz -C /mnt/target

2. Create necessary directories:
   sudo mkdir -p /mnt/target/{dev,proc,sys,run,tmp}

3. Set permissions:
   sudo chmod 1777 /mnt/target/tmp
   sudo chmod 755 /mnt/target/{dev,proc,sys,run}

4. Install bootloader (if needed):
   Configure GRUB or other bootloader to boot from /System/Library/Kernel/vmlinuz

EOF
    
    log "Manifest created: $manifest"
}

create_bootable_image() {
    hdr "Creating Bootable Disk Image"
    
    local image_path="$DIST_DIR/$IMAGE_NAME"
    local loop_dev=""
    local efi_part=""
    local root_part=""
    local mount_point="$MOCHI_BUILD/image-mount"
    
    log "Image: $image_path"
    log "Size: $IMAGE_SIZE"
    
    # Create sparse image file
    log "Creating disk image..."
    dd if=/dev/zero of="$image_path" bs=1 count=0 seek="$IMAGE_SIZE" 2>/dev/null
    
    # Create partition table
    log "Creating GPT partition table..."
    parted -s "$image_path" mklabel gpt
    parted -s "$image_path" mkpart ESP fat32 1MiB 513MiB
    parted -s "$image_path" set 1 esp on
    parted -s "$image_path" mkpart primary ext4 513MiB 100%
    
    # Setup loop device
    log "Setting up loop device..."
    loop_dev=$(losetup -fP --show "$image_path")
    log "Loop device: $loop_dev"
    
    # Wait for partition devices
    sleep 1
    partprobe "$loop_dev" 2>/dev/null || true
    sleep 1
    
    efi_part="${loop_dev}p1"
    root_part="${loop_dev}p2"
    
    # Format partitions
    log "Formatting EFI partition..."
    mkfs.vfat -F 32 -n MOCHIOS_EFI "$efi_part"
    
    log "Formatting root partition..."
    mkfs.ext4 -L MOCHIOS_ROOT "$root_part"
    
    # Get UUIDs
    local efi_uuid=$(blkid -s UUID -o value "$efi_part")
    local root_uuid=$(blkid -s UUID -o value "$root_part")
    
    log "EFI UUID: $efi_uuid"
    log "Root UUID: $root_uuid"
    
    # Mount partitions
    log "Mounting partitions..."
    mkdir -p "$mount_point"
    mount "$root_part" "$mount_point"
    
    # Copy rootfs first (excluding boot directory and build artifacts)
    log "Copying rootfs to image..."
    rsync -aHAX --info=progress2 \
        --exclude='/boot' \
        --exclude='/build' \
        --exclude='/sources' \
        --exclude='/cross' \
        --exclude='/host-bin' \
        --exclude='/host-lib64' \
        --exclude='/host-usrlib' \
        --exclude='/init' \
        --exclude='/scripts' \
        --exclude='/.buildstate' \
        --exclude='/lost+found' \
        "$MOCHI_ROOTFS/" "$mount_point/"
    
    # Handle boot directory specially
    log "Setting up boot directory..."
    rm -rf "$mount_point/boot"  # Remove any existing boot symlink/dir
    mkdir -p "$mount_point/boot/efi"
    mount "$efi_part" "$mount_point/boot/efi"
    
    # Update fstab with UUIDs
    log "Updating fstab with partition UUIDs..."
    cat > "$mount_point/System/etc/fstab" << EOF
# /etc/fstab: static file system information
#
# <file system>        <mount point>   <type>  <options>       <dump>  <pass>

# Root filesystem
UUID=$root_uuid        /               ext4    defaults        1       1

# EFI System Partition
UUID=$efi_uuid         /boot/efi       vfat    defaults        0       2

# Temporary filesystems
tmpfs                  /tmp            tmpfs   defaults,nodev,nosuid   0       0
tmpfs                  /run            tmpfs   defaults,nodev,nosuid   0       0
EOF
    
    # Install GRUB
    log "Installing GRUB bootloader..."
    
    # Create GRUB directory
    mkdir -p "$mount_point/boot/efi/EFI/BOOT"
    mkdir -p "$mount_point/System/Library/Kernel/grub"
    
    # Install GRUB to EFI partition
    if command -v grub-install >/dev/null 2>&1; then
        grub-install --target=x86_64-efi \
                     --efi-directory="$mount_point/boot/efi" \
                     --boot-directory="$mount_point/System/Library/Kernel" \
                     --removable \
                     --no-nvram \
                     "$loop_dev" || log "Warning: GRUB installation failed, creating manual config"
    else
        log "Warning: grub-install not found, creating manual GRUB config"
    fi
    
    # Create GRUB configuration
    log "Creating GRUB configuration..."
    cat > "$mount_point/System/Library/Kernel/grub/grub.cfg" << EOF
set default=0
set timeout=5

insmod part_gpt
insmod fat
insmod ext2

# Load video drivers
insmod all_video
insmod gfxterm
terminal_output gfxterm

menuentry "MochiOS" {
    search --no-floppy --set=root --fs-uuid $root_uuid
    linux  /System/Library/Kernel/vmlinuz root=UUID=$root_uuid rw quiet splash
}

menuentry "MochiOS (Recovery Mode)" {
    search --no-floppy --set=root --fs-uuid $root_uuid
    linux  /System/Library/Kernel/vmlinuz root=UUID=$root_uuid rw single init=/bin/bash
}

menuentry "MochiOS (Verbose Boot)" {
    search --no-floppy --set=root --fs-uuid $root_uuid
    linux  /System/Library/Kernel/vmlinuz root=UUID=$root_uuid rw debug
}
EOF
    
    # Sync and unmount
    log "Syncing filesystems..."
    sync
    
    log "Unmounting partitions..."
    umount "$mount_point/boot/efi"
    umount "$mount_point"
    
    # Detach loop device
    log "Detaching loop device..."
    losetup -d "$loop_dev"
    
    # Clean up mount point
    rmdir "$mount_point" 2>/dev/null || true
    
    # Get final image size
    local img_size=$(du -h "$image_path" | cut -f1)
    
    # Create checksum
    log "Generating checksum..."
    (cd "$DIST_DIR" && sha256sum "$IMAGE_NAME" > "$IMAGE_NAME.sha256")
    
    hdr "Bootable Image Created Successfully"
    log ""
    log "Image: $image_path"
    log "Size: $img_size"
    log "EFI UUID: $efi_uuid"
    log "Root UUID: $root_uuid"
    log "Checksum: $DIST_DIR/$IMAGE_NAME.sha256"
    log ""
    log "To write to USB/disk:"
    log "  sudo dd if=$image_path of=/dev/sdX bs=4M status=progress && sync"
    log ""
    log "To boot in QEMU:"
    log "  qemu-system-x86_64 -enable-kvm -m 2G -drive file=$image_path,format=raw -bios /usr/share/ovmf/OVMF.fd"
}

create_squashfs() {
    hdr "Creating SquashFS Image"
    
    local squashfs_path="$DIST_DIR/$DIST_NAME-$DIST_VERSION.squashfs"
    
    log "SquashFS: $squashfs_path"
    
    # Copy system config first
    copy_system_config
    
    # Create SquashFS with maximum compression
    log "Creating compressed SquashFS image..."
    log "  Excluding build artifacts and temporary files"
    
    mksquashfs "$MOCHI_ROOTFS" "$squashfs_path" \
        -comp xz \
        -Xbcj x86 \
        -b 1M \
        -noappend \
        -e build sources cross host-bin host-lib64 host-usrlib init scripts .buildstate lost+found \
        -e dev proc sys run tmp \
        -processors $(nproc)
    
    # Get final size
    local sqfs_size=$(du -h "$squashfs_path" | cut -f1)
    
    # Create checksum
    log "Generating checksum..."
    (cd "$DIST_DIR" && sha256sum "$DIST_NAME-$DIST_VERSION.squashfs" > "$DIST_NAME-$DIST_VERSION.squashfs.sha256")
    
    hdr "SquashFS Image Created Successfully"
    log ""
    log "SquashFS: $squashfs_path"
    log "Size: $sqfs_size"
    log "Checksum: $DIST_DIR/$DIST_NAME-$DIST_VERSION.squashfs.sha256"
    log ""
    log "To mount:"
    log "  sudo mount -t squashfs -o loop $squashfs_path /mnt"
    log ""
    log "To use as root filesystem:"
    log "  Add 'root=/dev/loop0' and use as initramfs overlay"
}

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Create distribution artifacts from the built MochiOS rootfs.

Commands:
  tarball           Create compressed rootfs tarball (default)
  image             Create bootable disk image (.img)
  squashfs          Create compressed SquashFS image
  all               Create tarball, image, and squashfs

Options:
  --name NAME       Distribution name (default: mochios-rootfs)
  --version VER     Version string (default: YYYYMMDD)
  --output DIR      Output directory (default: ./dist)
  --size SIZE       Image size for disk image (default: 1G)
  --manifest        Create manifest file (default: yes)
  --help            Show this help message

Examples:
  sudo ./dist.sh tarball
  sudo ./dist.sh image
  sudo ./dist.sh squashfs
  sudo ./dist.sh all
  sudo ./dist.sh image --size 8G --version 1.0.0
  sudo ./dist.sh tarball --output /tmp/dist

Environment Variables:
  MOCHI_BUILD       Build directory (default: ./buildfs)
  MOCHI_ROOTFS      Rootfs directory (default: \$MOCHI_BUILD/rootfs)
  DIST_DIR          Output directory (default: ./dist)
  IMAGE_SIZE        Disk image size (default: 1G)

EOF
}

main() {
    local create_manifest_file=true
    local command="tarball"
    
    # Parse command
    if [ $# -gt 0 ] && [[ ! "$1" =~ ^-- ]]; then
        command="$1"
        shift
    fi
    
    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --name)
                DIST_NAME="$2"
                shift 2
                ;;
            --version)
                DIST_VERSION="$2"
                shift 2
                ;;
            --output)
                DIST_DIR="$2"
                shift 2
                ;;
            --size)
                IMAGE_SIZE="$2"
                IMAGE_NAME="mochios-${DIST_VERSION}.img"
                shift 2
                ;;
            --manifest)
                create_manifest_file=true
                shift
                ;;
            --no-manifest)
                create_manifest_file=false
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    require_root
    
    # Execute command
    case "$command" in
        tarball)
            create_dist_tarball
            if [ "$create_manifest_file" = true ]; then
                create_manifest
            fi
            hdr "Tarball Distribution Complete"
            log "Ready for deployment!"
            ;;
        image)
            create_bootable_image
            hdr "Image Distribution Complete"
            log "Ready to boot!"
            ;;
        squashfs)
            create_squashfs
            hdr "SquashFS Distribution Complete"
            log "Ready for deployment!"
            ;;
        all)
            create_dist_tarball
            if [ "$create_manifest_file" = true ]; then
                create_manifest
            fi
            create_bootable_image
            create_squashfs
            hdr "All Distributions Complete"
            log "Tarball, image, and squashfs ready!"
            ;;
        *)
            echo "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
