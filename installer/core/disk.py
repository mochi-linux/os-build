import sys

from .tui import StatusBox, show_message
from .utils import confirm, get_disks, menu_select, run_command


def select_disk():
    disks = get_disks()
    if not disks:
        show_message("Error", "No disks found!")
        sys.exit(1)
    options = [
        f"{d['name']} - {d['size']} ({d.get('model', 'Unknown')})" for d in disks
    ]
    choice, idx = menu_select(options, "Select target disk")
    return disks[idx]


def partition_disk_auto(disk_path):
    if not confirm(
        f"!!! WARNING: This will ERASE all data on {disk_path} !!!\n\nProceed with automatic partitioning?"
    ):
        show_message("Installation Aborted", "Installation aborted.")
        sys.exit(0)

    with StatusBox("Partitioning", f"Partitioning {disk_path} ..."):
        # Using parted for simplicity
        run_command(["parted", "-s", disk_path, "mklabel", "gpt"])
        run_command(
            ["parted", "-s", disk_path, "mkpart", "ESP", "fat32", "1MiB", "512MiB"]
        )
        run_command(["parted", "-s", disk_path, "set", "1", "esp", "on"])
        run_command(
            ["parted", "-s", disk_path, "mkpart", "root", "ext4", "512MiB", "100%"]
        )

    return {
        "esp": f"{disk_path}1" if "nvme" not in disk_path else f"{disk_path}p1",
        "root": f"{disk_path}2" if "nvme" not in disk_path else f"{disk_path}p2",
    }


def format_partitions(partitions):
    with StatusBox(
        "Formatting", f"Formatting {partitions['esp']} as FAT32 ..."
    ) as status:
        run_command(["mkfs.fat", "-F", "32", "-n", "MOCHIOS_EFI", partitions["esp"]])

        status.update(f"Formatting {partitions['root']} as ext4 ...")
        run_command(["mkfs.ext4", "-F", "-L", "MOCHIOS_ROOT", partitions["root"]])
