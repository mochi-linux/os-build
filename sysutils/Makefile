# MochiOS System Utilities - Makefile
# Builds system utilities for MochiOS

# Compiler and flags
CC := gcc
CFLAGS := -Wall -Wextra -Werror -O2 -std=c11
LDFLAGS := -static
INSTALL_DIR := /sbin

# Subdirectories
SUBDIRS := powerctl

# Targets
.PHONY: all clean install install-rootfs help $(SUBDIRS)

all: $(SUBDIRS)

# Build powerctl
powerctl:
	@echo "Building powerctl..."
	@cd powerctl && \
		$(CC) $(CFLAGS) $(LDFLAGS) -o powerctl powerctl.c && \
		strip powerctl
	@echo "powerctl built successfully"

# Clean all builds
clean:
	@echo "Cleaning sysutils..."
	@rm -f powerctl/powerctl
	@echo "Clean complete"

# Install to system
install: all
	@echo "Installing system utilities to $(INSTALL_DIR)"
	@install -D -m 755 powerctl/powerctl $(INSTALL_DIR)/powerctl
	@ln -sf powerctl $(INSTALL_DIR)/poweroff
	@ln -sf powerctl $(INSTALL_DIR)/reboot
	@ln -sf powerctl $(INSTALL_DIR)/halt
	@echo "Installation complete"

# Install to rootfs (for build system)
install-rootfs: all
	@if [ -z "$(ROOTFS)" ]; then \
		echo "Error: ROOTFS variable not set"; \
		echo "Usage: make install-rootfs ROOTFS=/path/to/rootfs"; \
		exit 1; \
	fi
	@echo "Installing system utilities to $(ROOTFS)$(INSTALL_DIR)"
	@install -D -m 755 powerctl/powerctl $(ROOTFS)$(INSTALL_DIR)/powerctl
	@ln -sf powerctl $(ROOTFS)$(INSTALL_DIR)/poweroff
	@ln -sf powerctl $(ROOTFS)$(INSTALL_DIR)/reboot
	@ln -sf powerctl $(ROOTFS)$(INSTALL_DIR)/halt
	@echo "Installation complete"

# Show help
help:
	@echo "MochiOS System Utilities - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all              Build all utilities (default)"
	@echo "  powerctl         Build powerctl utility"
	@echo "  install          Install to system $(INSTALL_DIR)"
	@echo "  install-rootfs   Install to rootfs (requires ROOTFS=/path)"
	@echo "  clean            Remove build artifacts"
	@echo "  help             Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make"
	@echo "  make install"
	@echo "  make install-rootfs ROOTFS=../buildfs/rootfs"
	@echo "  make clean"
	@echo ""
	@echo "Utilities:"
	@echo "  powerctl         Power control (poweroff/reboot/halt)"
	@echo ""
	@echo "Build configuration:"
	@echo "  CC      = $(CC)"
	@echo "  CFLAGS  = $(CFLAGS)"
	@echo "  LDFLAGS = $(LDFLAGS)"
