{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  name = "mochios-build-env";

  buildInputs = with pkgs; [
    # Build essentials
    gcc
    gnumake
    binutils
    gawk
    bison
    flex
    m4
    patch

    # Compression tools
    gzip
    bzip2
    xz
    zlib

    # Build tools
    autoconf
    automake
    libtool
    pkg-config
    cmake

    # System utilities
    coreutils
    findutils
    gnused
    gnugrep
    gnutar
    diffutils

    # Perl and Python (for build scripts)
    perl
    python3

    # Text processing
    texinfo
    gettext

    # Version control
    git
    wget
    curl

    # Kernel build dependencies
    bc
    ncurses
    openssl
    elfutils
    kmod

    # GRUB dependencies
    grub2

    # Filesystem tools
    e2fsprogs
    dosfstools
    parted
    util-linux

    # Distributed compilation (icecc)
    icecream

    # Additional utilities
    rsync
    which
    file
    gmp
    mpfr
    libmpc
    isl
  ];

  shellHook = ''
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  MochiOS Build Environment (Nix)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "Available build commands:"
    echo "  ./scripts/buildworld.sh --help          Show build system help"
    echo "  ./scripts/buildworld.sh --host all      Build with local compilation"
    echo "  ./scripts/buildworld.sh --cluster all   Build with icecc distributed compilation"
    echo ""
    echo "Icecc cluster build:"
    echo "  icecc --version                 Check icecc installation"
    echo "  systemctl status iceccd         Check icecc daemon status"
    echo ""
    echo "Environment variables:"
    echo "  MOCHI_BUILD=${MOCHI_BUILD:-./buildfs}"
    echo "  MOCHI_TARGET=${MOCHI_TARGET:-x86_64-mochios-linux-gnu}"
    echo "  JOBS=${JOBS:-$(nproc)}"
    echo ""

    # Set up environment variables
    export MOCHI_BUILD="${MOCHI_BUILD:-$PWD/buildfs}"
    export MOCHI_TARGET="${MOCHI_TARGET:-x86_64-mochios-linux-gnu}"
    export JOBS="${JOBS:-$(nproc)}"

    # Ensure icecc is in PATH
    export PATH="${pkgs.icecream}/bin:$PATH"

    echo "Ready to build MochiOS!"
    echo ""
  '';

  # Environment variables for the build
  MOCHI_BUILD = "./buildfs";
  MOCHI_TARGET = "x86_64-mochios-linux-gnu";
  BUILD_MODE = "host";

  # Disable hardening for cross-compilation
  hardeningDisable = [ "all" ];

  # Allow unfree packages if needed
  NIXPKGS_ALLOW_UNFREE = "1";
}
