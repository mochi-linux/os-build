{
  description = "MochiOS - Custom Linux Distribution Build System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        devShells.default = pkgs.mkShell {
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

            # Perl and Python
            perl
            python3

            # Text processing
            texinfo
            gettext

            # Version control and download tools
            git
            wget
            curl

            # Kernel build dependencies
            bc
            ncurses
            openssl
            elfutils
            kmod

            # GRUB bootloader
            grub2

            # Filesystem tools
            e2fsprogs
            dosfstools
            parted
            util-linux

            # Distributed compilation (icecc/icecream)
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
            cat << 'EOF'
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              MochiOS Build Environment (Nix Flake)
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            Build Commands:
              cd ..                           Go to build root
              ./scripts/buildworld.sh --help          Show build system help
              ./scripts/buildworld.sh fetch           Download all source packages
              ./scripts/buildworld.sh --host all      Full build (local compilation)
              ./scripts/buildworld.sh --cluster all   Full build (icecc distributed)

            Build Steps:
              ./scripts/buildworld.sh rootfs          Create rootfs directory layout
              ./scripts/buildworld.sh host            Build cross-toolchain
              ./scripts/buildworld.sh populate        Populate rootfs with basics
              ./scripts/buildworld.sh chroot          Build system in chroot
              ./scripts/buildworld.sh image           Create bootable disk image

            Cluster Build (icecc):
              icecc --version                 Check icecc installation
              icecc --help                    Show icecc help

            Utilities:
              ./umount-all.sh                 Unmount all build bind mounts
              make -C sysutils                Build system utilities
              make -C sysutils clean          Clean system utilities

            System Utilities:
              launcher                        .app bundle launcher
              mkappbundle                     .app bundle creator
              powerctl                        Power management (poweroff/reboot/halt)

            Environment:
              MOCHI_BUILD    = ${MOCHI_BUILD:-./buildfs}
              MOCHI_TARGET   = ${MOCHI_TARGET:-x86_64-mochios-linux-gnu}
              JOBS           = ${JOBS:-$(nproc)}
              BUILD_MODE     = ${BUILD_MODE:-host}

            Ready to build MochiOS!
            EOF

            # Set up environment variables
            export MOCHI_BUILD="${MOCHI_BUILD:-$PWD/buildfs}"
            export MOCHI_TARGET="${MOCHI_TARGET:-x86_64-mochios-linux-gnu}"
            export JOBS="${JOBS:-$(nproc)}"
            export BUILD_MODE="${BUILD_MODE:-host}"

            # Ensure icecc is available
            export PATH="${pkgs.icecream}/bin:$PATH"

            # Change to parent directory (os-build root)
            if [ -f "../scripts/buildworld.sh" ]; then
              cd ..
            fi

            # Add current directory to PATH for build scripts
            export PATH="$PWD:$PATH"
          '';

          # Environment variables
          MOCHI_BUILD = "./buildfs";
          MOCHI_TARGET = "x86_64-mochios-linux-gnu";
          BUILD_MODE = "host";

          # Disable hardening for cross-compilation
          hardeningDisable = [ "all" ];

          # Allow unfree packages if needed
          NIXPKGS_ALLOW_UNFREE = "1";
        };

        # Alias for convenience
        devShell = self.devShells.${system}.default;
      }
    );
}
