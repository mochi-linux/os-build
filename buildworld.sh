#!/usr/bin/env bash
# MochiOS - Full System Build Orchestrator
#
# Build pipeline:
#   HOST  : headers → binutils → gcc(stage1) → glibc → gcc(stage2)
#   CHROOT: bash → coreutils → system → kernel → grub
#   IMAGE : GPT disk image (EFI + ext4 root)

set -euo pipefail

# Cleanup trap for error handling
cleanup_on_error() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo ""
        echo "════════════════════════════════════════════════════════════"
        echo "  BUILD FAILED (exit code: $exit_code)"
        echo "  Cleaning up mounts..."
        echo "════════════════════════════════════════════════════════════"
        _umount_chroot 2>/dev/null || true
        echo "  Cleanup complete. You can restart the build."
        echo "════════════════════════════════════════════════════════════"
    fi
}

trap cleanup_on_error EXIT ERR

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
: "${JOBS:=$(($(nproc)*2+8))}"
: "${ARIA2_CONNECTIONS:=16}"
: "${ARIA2_SPLITS:=16}"
: "${ARIA2_MIN_SPLIT:=1M}"
: "${ARIA2_PARALLEL:=4}"
: "${ARIA2_RPC_PORT:=6800}"
: "${ARIA2_RPC_TOKEN:=mochi-dl}"

export MOCHI_BUILD MOCHI_SOURCES MOCHI_SYSROOT MOCHI_ROOTFS \
       MOCHI_CROSS MOCHI_TARGET MOCHI_IMAGE JOBS \
       ARIA2_CONNECTIONS ARIA2_SPLITS ARIA2_MIN_SPLIT \
       ARIA2_PARALLEL ARIA2_RPC_PORT ARIA2_RPC_TOKEN

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Source URLs  (from SOURCES.txt)
# ---------------------------------------------------------------------------
SOURCES_LIST=(
    "https://git.kernel.org/torvalds/t/linux-7.0-rc6.tar.gz"
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
    "https://mirror.cyberbits.asia/gnu/autoconf/autoconf-latest.tar.xz"
    "https://www.cpan.org/src/5.0/perl-5.42.1.tar.gz"
    "https://ftp.gnu.org/gnu/automake/automake-1.17.tar.gz"
    "https://ftp.gnu.org/gnu/libtool/libtool-2.5.4.tar.xz"
    "https://www.openssl.org/source/openssl-3.4.0.tar.gz"
    "https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
    "https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz"
    "https://sourceware.org/elfutils/ftp/0.192/elfutils-0.192.tar.bz2"
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

_ensure_host_devpts() {
    if ! mountpoint -q /dev/pts 2>/dev/null; then
        mkdir -p /dev/pts
        mount -t devpts devpts /dev/pts -o gid=5,mode=0620,ptmxmode=0666
    fi
    if [ ! -e /dev/ptmx ]; then
        ln -sfn /dev/pts/ptmx /dev/ptmx
    fi
}

# ---------------------------------------------------------------------------
# Download backend
# ---------------------------------------------------------------------------

# Fallback: single-file sequential download via wget or curl
_download_single() {
    local url="$1"
    local dest="$2"
    local tmp="${dest}.part"
    if command -v wget >/dev/null 2>&1; then
        wget --show-progress -q -O "$tmp" "$url" && mv "$tmp" "$dest"
    elif command -v curl >/dev/null 2>&1; then
        curl -L --progress-bar -o "$tmp" "$url" && mv "$tmp" "$dest"
    else
        die "No download tool found. Install aria2, wget, or curl."
    fi
}

# Parallel batch download via aria2c JSON-RPC + jq progress display
# Usage: _aria2_rpc_fetch <input-file>
#   input-file format (aria2c -i format):
#     https://example.com/file.tar.gz
#       out=file.tar.gz
_aria2_rpc_fetch() {
    local input_file="$1"
    local rpc_base="http://127.0.0.1:${ARIA2_RPC_PORT}/jsonrpc"
    local auth="token:${ARIA2_RPC_TOKEN}"

    # Start aria2c with JSON-RPC in background
    aria2c \
        --input-file="$input_file" \
        --dir="$MOCHI_SOURCES" \
        --split="$ARIA2_SPLITS" \
        --max-connection-per-server="$ARIA2_CONNECTIONS" \
        --min-split-size="$ARIA2_MIN_SPLIT" \
        --max-concurrent-downloads="$ARIA2_PARALLEL" \
        --file-allocation=none \
        --continue=true \
        --enable-rpc=true \
        --rpc-listen-all=false \
        --rpc-listen-port="$ARIA2_RPC_PORT" \
        --rpc-secret="$ARIA2_RPC_TOKEN" \
        --quiet=true \
        --log="/tmp/aria2-mochi.log" \
        --log-level=warn &
    local aria2_pid=$!

    # Kill aria2c on unexpected exit
    trap "kill $aria2_pid 2>/dev/null; trap - EXIT INT TERM" EXIT INT TERM

    # Wait for RPC to become ready (max 5 seconds)
    local tries=0
    until curl -sf --max-time 1 "$rpc_base" \
        -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"aria2.getVersion\",\"params\":[\"${auth}\"]}" \
        >/dev/null 2>&1; do
        sleep 0.2
        tries=$((tries+1))
        [ "$tries" -gt 25 ] && die "aria2c RPC did not start on port ${ARIA2_RPC_PORT}"
    done

    log "aria2c RPC ready  (pid $aria2_pid  port ${ARIA2_RPC_PORT}  parallel ${ARIA2_PARALLEL})"
    echo ""

    # ---------------------------------------------------------------------------
    # Progress monitor: poll JSON-RPC, parse with jq
    # ---------------------------------------------------------------------------
    while true; do

        # -- Global statistics --
        local gstat
        gstat=$(curl -sf --max-time 2 "$rpc_base" \
            --data-raw "{\"jsonrpc\":\"2.0\",\"id\":1,\
\"method\":\"aria2.getGlobalStat\",\
\"params\":[\"${auth}\"]}" 2>/dev/null) || { sleep 1; continue; }

        local num_active num_waiting num_done speed_kbps
        num_active=$( echo "$gstat" | jq -r '.result.numActive')
        num_waiting=$(echo "$gstat" | jq -r '.result.numWaiting')
        num_done=$(   echo "$gstat" | jq -r '.result.numStoppedTotal')
        speed_kbps=$( echo "$gstat" | jq -r '(.result.downloadSpeed | tonumber / 1024 | floor)')

        # -- Per-file active download details --
        local active_json
        active_json=$(curl -sf --max-time 2 "$rpc_base" \
            --data-raw "{\"jsonrpc\":\"2.0\",\"id\":2,\
\"method\":\"aria2.tellActive\",\
\"params\":[\"${auth}\",[\"gid\",\"completedLength\",\"totalLength\",\"downloadSpeed\",\"files\"]]}" \
            2>/dev/null) || active_json='{"result":[]}'

        # -- Render progress table --
        printf "\033[2K\r"
        printf "[aria2c] %6d KB/s | active:%-2s waiting:%-2s done:%-3s\n" \
            "$speed_kbps" "$num_active" "$num_waiting" "$num_done"

        echo "$active_json" | jq -r '
          .result[] |
          (.files[0].path | split("/") | last) as $name |
          (.completedLength | tonumber)          as $done |
          (.totalLength     | tonumber)          as $total |
          (.downloadSpeed   | tonumber / 1024 | floor) as $spd |
          (if $total > 0 then ($done * 100 / $total | floor) else 0 end) as $pct |
          (if $total > 0 then ($total / 1048576 | floor | tostring) + " MB" else "?" end) as $size |
          "  \($name)  \($pct)%  [\($done / 1048576 * 10 | floor | . / 10)/\($size)]  \($spd) KB/s"
        ' 2>/dev/null || true

        # Exit loop when nothing left
        if [ "$num_active" = "0" ] && [ "$num_waiting" = "0" ]; then
            echo ""
            log "All downloads complete."
            break
        fi

        sleep 1
    done

    # Graceful shutdown via RPC; fall back to SIGTERM if RPC call fails
    curl -sf --max-time 5 "$rpc_base" \
        --data-raw "{\"jsonrpc\":\"2.0\",\"id\":99,\"method\":\"aria2.shutdown\",\"params\":[\"${auth}\"]}" \
        >/dev/null 2>&1 || kill "$aria2_pid" 2>/dev/null || true

    wait "$aria2_pid" 2>/dev/null || true
    trap - EXIT INT TERM
}

# ---------------------------------------------------------------------------
# Source fetch & extract
# ---------------------------------------------------------------------------
_extract() {
    local archive="$1"
    local dest="$MOCHI_SOURCES/$archive"
    log "Extracting: $archive"
    case "$archive" in
        *.tar.xz)  tar -xJf "$dest" -C "$MOCHI_SOURCES" ;;
        *.tar.gz)  tar -xzf "$dest" -C "$MOCHI_SOURCES" ;;
        *.tar.bz2) tar -xjf "$dest" -C "$MOCHI_SOURCES" ;;
        *.zip)     unzip -q "$dest" -d "$MOCHI_SOURCES" ;;
        *) die "Unknown archive format: $archive" ;;
    esac
}

_archive_dirname() {
    local archive="$1"
    local d="$archive"
    d="${d%.tar.xz}"
    d="${d%.tar.gz}"
    d="${d%.tar.bz2}"
    d="${d%.zip}"
    echo "$d"
}

cmd_fetch() {
    hdr "Downloading Sources"
    mkdir -p "$MOCHI_SOURCES"

    if command -v aria2c >/dev/null 2>&1; then
        # ----------------------------------------------------------------
        # aria2c parallel path
        # ----------------------------------------------------------------
        if ! command -v jq >/dev/null 2>&1; then
            log "WARNING: jq not found – progress display disabled (run setup script to install jq)"
        fi

        log "Backend  : aria2c"
        log "Settings : ${ARIA2_PARALLEL} files in parallel  |  ${ARIA2_CONNECTIONS} conn/file  |  ${ARIA2_SPLITS} splits  |  min-split ${ARIA2_MIN_SPLIT}"

        # Build aria2c input file for files not yet downloaded
        local input_file
        input_file=$(mktemp /tmp/aria2-mochi-XXXXXX.txt)
        local need_download=0

        for url in "${SOURCES_LIST[@]}"; do
            local archive
            archive="$(basename "$url")"
            if [ ! -f "$MOCHI_SOURCES/$archive" ]; then
                printf '%s\n  out=%s\n' "$url" "$archive" >> "$input_file"
                need_download=$((need_download+1))
                log "  queued : $archive"
            else
                log "  cached : $archive"
            fi
        done

        if [ "$need_download" -gt 0 ]; then
            log "Starting parallel download of $need_download file(s) ..."
            echo ""
            if command -v jq >/dev/null 2>&1; then
                _aria2_rpc_fetch "$input_file"
            else
                # jq absent – run aria2c directly without RPC progress
                aria2c \
                    --input-file="$input_file" \
                    --dir="$MOCHI_SOURCES" \
                    --split="$ARIA2_SPLITS" \
                    --max-connection-per-server="$ARIA2_CONNECTIONS" \
                    --min-split-size="$ARIA2_MIN_SPLIT" \
                    --max-concurrent-downloads="$ARIA2_PARALLEL" \
                    --file-allocation=none \
                    --continue=true \
                    --console-log-level=notice \
                    --summary-interval=5
            fi
        else
            log "All archives already cached – skipping download."
        fi

        rm -f "$input_file"

    elif command -v wget >/dev/null 2>&1 || command -v curl >/dev/null 2>&1; then
        # ----------------------------------------------------------------
        # Sequential fallback (wget / curl)
        # ----------------------------------------------------------------
        local backend
        backend=$(command -v wget >/dev/null 2>&1 && echo wget || echo curl)
        log "Backend  : $backend  (sequential – install aria2 for parallel downloads)"

        for url in "${SOURCES_LIST[@]}"; do
            local archive
            archive="$(basename "$url")"
            local dest="$MOCHI_SOURCES/$archive"
            if [ -f "$dest" ]; then
                log "  cached : $archive"
            else
                log "  fetch  : $archive"
                _download_single "$url" "$dest"
            fi
        done
    else
        die "No download tool found. Install aria2, wget, or curl."
    fi

    # ----------------------------------------------------------------
    # Extract all archives
    # ----------------------------------------------------------------
    log ""
    log "Extracting archives ..."
    for url in "${SOURCES_LIST[@]}"; do
        local archive dirname
        archive="$(basename "$url")"
        dirname="$(_archive_dirname "$archive")"
        if [ ! -d "$MOCHI_SOURCES/$dirname" ]; then
            _extract "$archive"
        else
            log "  already extracted : $dirname"
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
    ln -sfn lib       "$MOCHI_ROOTFS/System/usr/lib64" 2>/dev/null || true
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
# Rootfs Bootstrap  (cross-compile bash+coreutils → rootfs, copy glibc libs)
# ---------------------------------------------------------------------------
cmd_populate() {
    hdr "Populating Rootfs (bootstrap tools)"
    export PATH="$MOCHI_CROSS/bin:$PATH"
    bash "$SCRIPT_DIR/scripts/host/populate.sh"
}

# ---------------------------------------------------------------------------
# HOST toolchain
# ---------------------------------------------------------------------------
cmd_host() {
    local step="${1:-all}"
    hdr "HOST Toolchain: $step"
    export PATH="$MOCHI_CROSS/bin:$PATH"
    export BUILD_MODE="${BUILD_MODE:-host}"
    bash "$SCRIPT_DIR/scripts/host/buildsource.sh" "$step"
}

# ---------------------------------------------------------------------------
# CHROOT utilities
# ---------------------------------------------------------------------------
_mount_chroot() {
    mount --bind /dev             "$MOCHI_ROOTFS/dev"
    mount -t devpts devpts        "$MOCHI_ROOTFS/dev/pts" -o gid=5,mode=0620,ptmxmode=0666
    mount -t proc   proc          "$MOCHI_ROOTFS/proc"
    mount -t sysfs  sysfs         "$MOCHI_ROOTFS/sys"
    mount -t tmpfs  tmpfs         "$MOCHI_ROOTFS/run"
    mount -t tmpfs  tmpfs         "$MOCHI_ROOTFS/tmp"
}

_umount_chroot() {
    # Use lazy unmount (-l) to handle busy mounts and prevent mount point exhaustion
    umount -l -R "$MOCHI_ROOTFS/dev"          2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/proc"         2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/sys"          2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/run"          2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/tmp"          2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/sources"      2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/build"        2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/cross"        2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/host-bin"     2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/host-lib64"   2>/dev/null || true
    umount -l    "$MOCHI_ROOTFS/host-usrlib"  2>/dev/null || true
    
    # Give kernel time to clean up lazy unmounts
    sleep 0.5
}

# Mount the cross-compiler and host fallback tools into the chroot, then
# create thin wrapper scripts so 'gcc', 'cc', 'g++', etc. work natively.
_setup_chroot_toolchain() {
    # Find the real path of the host's dynamic linker
    local host_ld
    for _try in /lib64/ld-linux-x86-64.so.2 \
                /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 \
                /usr/lib/ld-linux-x86-64.so.2; do
        if [ -e "$_try" ]; then
            host_ld=$(readlink -f "$_try" 2>/dev/null || echo "$_try")
            break
        fi
    done
    : "${host_ld:=/lib64/ld-linux-x86-64.so.2}"
    local host_lib64_dir
    host_lib64_dir=$(dirname "$host_ld")

    # Bind-mount the cross-compiler tree
    mkdir -p "$MOCHI_ROOTFS/cross"
    mount --bind "$MOCHI_CROSS" "$MOCHI_ROOTFS/cross"

    # Bind-mount host /usr/bin for fallback tools (sed, grep, awk, make …)
    mkdir -p "$MOCHI_ROOTFS/host-bin"
    mount --bind /usr/bin "$MOCHI_ROOTFS/host-bin"

    # Bind-mount the directory containing the host ld-linux + glibc so the
    # cross-compiler binary can resolve its own shared-library dependencies.
    mkdir -p "$MOCHI_ROOTFS/host-lib64"
    mount --bind "$host_lib64_dir" "$MOCHI_ROOTFS/host-lib64"

    # Also mount /usr/lib for extra host libraries (mpc, mpfr, gmp, z, …)
    mkdir -p "$MOCHI_ROOTFS/host-usrlib"
    mount --bind /usr/lib "$MOCHI_ROOTFS/host-usrlib" 2>/dev/null || true

    local chroot_ld="/host-lib64/$(basename "$host_ld")"
    local chroot_lp="/host-lib64:/host-usrlib"

    # Write thin wrappers into the rootfs so the chroot sees a native toolchain
    local wrap_dir="$MOCHI_ROOTFS/usr/bin"
    mkdir -p "$wrap_dir"

    for _t in gcc cc; do
        printf '#!/bin/sh\nexec %s --library-path %s /cross/bin/%s-gcc --sysroot=/ -Wl,-rpath,/usr/lib "$@"\n' \
            "$chroot_ld" "$chroot_lp" "$MOCHI_TARGET" > "$wrap_dir/$_t"
        chmod +x "$wrap_dir/$_t"
    done

    for _t in g++ c++; do
        printf '#!/bin/sh\nexec %s --library-path %s /cross/bin/%s-g++ --sysroot=/ -Wl,-rpath,/usr/lib "$@"\n' \
            "$chroot_ld" "$chroot_lp" "$MOCHI_TARGET" > "$wrap_dir/$_t"
        chmod +x "$wrap_dir/$_t"
    done

    for _b in ar nm ranlib strip ld objdump objcopy readelf; do
        printf '#!/bin/sh\nexec %s --library-path %s /cross/bin/%s-%s "$@"\n' \
            "$chroot_ld" "$chroot_lp" "$MOCHI_TARGET" "$_b" > "$wrap_dir/$_b"
        chmod +x "$wrap_dir/$_b"
    done

    log "Chroot toolchain wrappers created (cross → $MOCHI_TARGET, sysroot=/)"
}

_enter_chroot() {
    local step="$1"
    
    # Clean up any existing mounts first to prevent mount point exhaustion
    _umount_chroot

    # Inject build scripts into rootfs
    mkdir -p "$MOCHI_ROOTFS/scripts/chroot"
    cp "$SCRIPT_DIR/scripts/chroot/buildsource.sh" \
       "$MOCHI_ROOTFS/scripts/chroot/buildsource.sh"
    chmod +x "$MOCHI_ROOTFS/scripts/chroot/buildsource.sh"
    
    # Copy init source into rootfs for building
    if [ -d "$SCRIPT_DIR/init" ]; then
        log "Copying init source to rootfs"
        rm -rf "$MOCHI_ROOTFS/init"
        cp -r "$SCRIPT_DIR/init" "$MOCHI_ROOTFS/init"
    fi

    # Stage kernel config into sources so it is visible at /sources/mochi.config
    local kconfig_src="$SCRIPT_DIR/config/mochi.config"
    if [ -f "$kconfig_src" ]; then
        mkdir -p "$MOCHI_SOURCES"
        cp "$kconfig_src" "$MOCHI_SOURCES/mochi.config"
        log "Kernel config staged → $MOCHI_SOURCES/mochi.config"
    else
        log "WARNING: config/mochi.config not found; kernel will use defconfig fallback"
    fi

    # Bind-mount sources and build temp dir into chroot
    mkdir -p "$MOCHI_ROOTFS/sources" "$MOCHI_ROOTFS/build"
    mount --bind "$MOCHI_SOURCES"      "$MOCHI_ROOTFS/sources"
    mount -o remount,bind,exec "$MOCHI_ROOTFS/sources" 2>/dev/null || true
    mount --bind "$MOCHI_BUILD/build"  "$MOCHI_ROOTFS/build"  2>/dev/null || \
        mount -t tmpfs -o exec tmpfs "$MOCHI_ROOTFS/build"
    mount -o remount,bind,exec "$MOCHI_ROOTFS/build" 2>/dev/null || true

    _setup_chroot_toolchain
    _mount_chroot

    local chroot_env=(
        HOME=/root
        TERM="${TERM:-xterm}"
        PS1='(mochios) \u:\w\$ '
        PATH=/usr/bin:/usr/sbin:/bin:/sbin:/host-bin
        LD_LIBRARY_PATH=/host-lib64:/host-usrlib
        MOCHI_SOURCES=/sources
        MOCHI_BUILD=/build
        MOCHI_KCONFIG=/sources/mochi.config
        JOBS="$JOBS"
        BUILD_MODE="${BUILD_MODE:-host}"
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
    _ensure_host_devpts
    mkdir -p "$MOCHI_BUILD/build"
    _enter_chroot "$step"
}

# ---------------------------------------------------------------------------
# Shell (interactive chroot)
# ---------------------------------------------------------------------------
cmd_shell() {
    hdr "MochiOS Chroot Shell"
    require_root
    _ensure_host_devpts
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
Usage: $0 [OPTIONS] [COMMAND] [STEP]

Options:
  --host           Use host build mode (local compilation, default)
  --cluster        Use cluster build mode (icecc distributed compilation)

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
  populate         Cross-compile bash+coreutils into rootfs; copy glibc libs
  all              Full pipeline: fetch → rootfs → host → populate → chroot → image

Environment variables:
  MOCHI_BUILD      Build root dir    (default: ./buildfs)
  MOCHI_TARGET     Cross triplet     (default: x86_64-mochios-linux-gnu)
  MOCHI_IMAGE      Output image path (default: \$MOCHI_BUILD/mochios.img)
  IMG_SIZE_MB      Disk image size   (default: 4096)
  EFI_SIZE_MB      EFI partition     (default: 512)
  JOBS             Parallel jobs     (default: nproc)
  BUILD_MODE       Build mode        (default: host, options: host|cluster)

Examples:
  $0 all                   # Full build (host mode)
  $0 --cluster all         # Full build with icecc cluster
  $0 --host host           # Build entire host toolchain locally
  $0 --cluster host gcc1   # Build only GCC stage 1 with cluster
  $0 --cluster chroot kernel  # Build kernel with cluster
  $0 chroot system         # Build only system utilities in chroot
  $0 image                 # Create disk image from existing rootfs
  JOBS=8 $0 host           # Use 8 parallel jobs

Build pipeline:
  HOST  : headers → binutils → gcc(stage1) → glibc → gcc(stage2)
  CHROOT: bash → coreutils → system → kernel → grub
  IMAGE : GPT (512MiB EFI + ext4 root)

Cluster build mode:
  --cluster uses icecc for distributed compilation across build nodes.
  Requires icecc to be installed and configured on the build host.
  Kernel builds use: make -j\$(nproc) CC="icecc gcc"
  Configure scripts use: CC="icecc gcc" ./configure ...
EOF
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    # Parse options
    export BUILD_MODE="host"  # default
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --host)
                BUILD_MODE="host"
                shift
                ;;
            --cluster)
                BUILD_MODE="cluster"
                shift
                ;;
            --*)
                die "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done

    local cmd="${1:-all}"
    local step="${2:-all}"

    log "MochiOS Build System"
    log "  Build root : $MOCHI_BUILD"
    log "  Target     : $MOCHI_TARGET"
    log "  Jobs       : $JOBS"
    log "  Build mode : $BUILD_MODE"

    case "$cmd" in
        fetch)        cmd_fetch ;;
        rootfs)       cmd_rootfs ;;
        host)         cmd_host "$step" ;;
        populate)     cmd_populate ;;
        chroot)       cmd_chroot "$step" ;;
        image)        cmd_image ;;
        shell)        cmd_shell ;;
        clean)        cmd_clean ;;
        distclean)    cmd_distclean ;;
        all)
            cmd_fetch
            cmd_rootfs
            cmd_host all
            cmd_populate
            cmd_chroot all
            cmd_image
            ;;
        help|-h|--help) usage ;;
        *)  usage; die "Unknown command: '$cmd'" ;;
    esac

    log "==> Done"
}

main "$@"
