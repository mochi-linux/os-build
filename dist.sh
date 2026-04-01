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

create_dist_tarball() {
    hdr "MochiOS Distribution Builder"
    
    log "Rootfs path: $MOCHI_ROOTFS"
    log "Output directory: $DIST_DIR"
    log "Distribution name: $DIST_NAME-$DIST_VERSION"
    
    # Verify rootfs exists
    if [ ! -d "$MOCHI_ROOTFS" ]; then
        die "Rootfs not found at $MOCHI_ROOTFS. Run buildworld.sh first."
    fi
    
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

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Create a distribution tarball from the built MochiOS rootfs.

Options:
  --name NAME       Distribution name (default: mochios-rootfs)
  --version VER     Version string (default: YYYYMMDD)
  --output DIR      Output directory (default: ./dist)
  --manifest        Create manifest file (default: yes)
  --help            Show this help message

Examples:
  sudo ./dist.sh
  sudo ./dist.sh --name mochios --version 1.0.0
  sudo ./dist.sh --output /tmp/dist

Environment Variables:
  MOCHI_BUILD       Build directory (default: ./buildfs)
  MOCHI_ROOTFS      Rootfs directory (default: \$MOCHI_BUILD/rootfs)
  DIST_DIR          Output directory (default: ./dist)

EOF
}

main() {
    local create_manifest_file=true
    
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
    create_dist_tarball
    
    if [ "$create_manifest_file" = true ]; then
        create_manifest
    fi
    
    hdr "Distribution Build Complete"
    log "Ready for deployment!"
}

main "$@"
