#!/usr/bin/env python3
import argparse
import os
import sys

from core.config import set_hostname, set_root_password
from core.disk import format_partitions, partition_disk_auto, select_disk
from core.tui import confirm, init_tui, input_password, input_text, show_message
from fs.install import (
    finalize_installation,
    install_rootfs,
    mount_partitions,
    setup_bootloader,
)


def welcome():
    text = (
        "This script will guide you through the installation.\n"
        "Please ensure you have backed up any important data."
    )
    show_message("Welcome to MochiOS Installer", text)


@init_tui
def main(args):
    if os.getuid() != 0:
        show_message("Error", "Installer must be run as root.")
        sys.exit(1)

    welcome()

    # Step 1: Disk Selection
    disk = select_disk()
    disk_path = disk["name"]

    # Step 2: Partitioning
    partitions = partition_disk_auto(disk_path)

    # Step 3: Formatting
    format_partitions(partitions)

    # Step 4: Mounting
    target_mount, esp_mount = mount_partitions(partitions)

    try:
        # Step 5: Install Rootfs
        # In a real live environment, the source might be different
        source_rootfs = args.source
        if not os.path.exists(source_rootfs):
            source_rootfs = input_text(
                "Source Rootfs",
                f"Warning: Source rootfs {source_rootfs} not found.\nPlease enter path to source rootfs:",
            )

        install_rootfs(source_rootfs, target_mount)

        # Step 6: Configuration
        hostname = (
            input_text("Hostname", "Enter hostname:", default="mochios") or "mochios"
        )
        set_hostname(target_mount, hostname)

        while True:
            password = input_password("Root Password", "Enter root password:")
            confirm_password = input_password("Root Password", "Confirm root password:")
            if password == confirm_password and password:
                break
            show_message("Error", "Passwords do not match or are empty. Try again.")

        set_root_password(target_mount, password)

        # Step 7: Bootloader
        setup_bootloader(target_mount, esp_mount)

        show_message("Success", "Installation successful!")
        if confirm("Reboot", "Would you like to reboot now?"):
            os.system("reboot")

    finally:
        finalize_installation(target_mount, esp_mount)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MochiOS Installer")
    parser.add_argument(
        "--source",
        help="Source rootfs directory",
        default="/run/mochi-installer/rootfs",
    )
    parsed_args = parser.parse_args()
    main(parsed_args)
