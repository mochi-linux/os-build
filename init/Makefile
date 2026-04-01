# MochiOS Init - Makefile
# Builds the system init process

# Compiler and flags
CC := gcc
CFLAGS := -Wall -Wextra -Werror -O2 -std=c11
LDFLAGS := -static
TARGET := init

# Directories
SRC_DIR := src
BUILD_DIR := build
INSTALL_DIR := /sbin

# Source files
SOURCES := $(wildcard $(SRC_DIR)/*.c)
OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(BUILD_DIR)/%.o)

# Default target
.PHONY: all
all: $(BUILD_DIR)/$(TARGET)

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Compile object files
$(BUILD_DIR)/%.o: $(SRC_DIR)/%.c | $(BUILD_DIR)
	@echo "  CC      $<"
	@$(CC) $(CFLAGS) -c $< -o $@

# Link final binary
$(BUILD_DIR)/$(TARGET): $(OBJECTS)
	@echo "  LD      $@"
	@$(CC) $(LDFLAGS) $(OBJECTS) -o $@
	@echo "  STRIP   $@"
	@strip $@
	@echo ""
	@echo "Build complete: $@"
	@ls -lh $@

# Install to system
.PHONY: install
install: $(BUILD_DIR)/$(TARGET)
	@echo "Installing $(TARGET) to $(INSTALL_DIR)"
	@install -D -m 755 $(BUILD_DIR)/$(TARGET) $(INSTALL_DIR)/$(TARGET)
	@echo "Installation complete"

# Install to rootfs (for build system)
.PHONY: install-rootfs
install-rootfs: $(BUILD_DIR)/$(TARGET)
	@if [ -z "$(ROOTFS)" ]; then \
		echo "Error: ROOTFS variable not set"; \
		echo "Usage: make install-rootfs ROOTFS=/path/to/rootfs"; \
		exit 1; \
	fi
	@echo "Installing $(TARGET) to $(ROOTFS)$(INSTALL_DIR)"
	@install -D -m 755 $(BUILD_DIR)/$(TARGET) $(ROOTFS)$(INSTALL_DIR)/$(TARGET)
	@echo "Installation complete"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts"
	@rm -rf $(BUILD_DIR)
	@echo "Clean complete"

# Show help
.PHONY: help
help:
	@echo "MochiOS Init - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all              Build init binary (default)"
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
	@echo "Build configuration:"
	@echo "  CC      = $(CC)"
	@echo "  CFLAGS  = $(CFLAGS)"
	@echo "  LDFLAGS = $(LDFLAGS)"

# Debug target - show variables
.PHONY: debug
debug:
	@echo "Sources: $(SOURCES)"
	@echo "Objects: $(OBJECTS)"
	@echo "Target:  $(BUILD_DIR)/$(TARGET)"
