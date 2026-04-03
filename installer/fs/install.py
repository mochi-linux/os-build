import os

from core.tui import StatusBox
from core.utils import run_command


def mount_partitions(partitions, mount_point="/mnt/mochi-root"):
    with StatusBox(
        "Mounting", f"Mounting {partitions['root']} to {mount_point} ..."
    ) as status:
        if not os.path.exists(mount_point):
            os.makedirs(mount_point)

        run_command(["mount", partitions["root"], mount_point])

        esp_mount = os.path.join(mount_point, "boot")
        if not os.path.exists(esp_mount):
            os.makedirs(esp_mount)

        status.update(f"Mounting {partitions['esp']} to {esp_mount} ...")
        run_command(["mount", partitions["esp"], esp_mount])
        return mount_point, esp_mount


def install_rootfs(source_rootfs, target_mount):
    with StatusBox(
        "Installing Rootfs",
        f"Installing rootfs from {source_rootfs} to {target_mount} ...",
    ):
        # rsync is reliable for this
        run_command(
            [
                "rsync",
                "-aHAX",
                "--exclude='/dev/*'",
                "--exclude='/proc/*'",
                "--exclude='/sys/*'",
                "--exclude='/run/*'",
                "--exclude='/tmp/*'",
                "--exclude='/sources'",
                "--exclude='/build'",
                f"{source_rootfs}/",
                f"{target_mount}/",
            ]
        )


def setup_bootloader(target_mount, esp_mount):
    with StatusBox("Bootloader", "Installing GRUB bootloader ..."):
        # MochiOS structure from createimage.sh
        # Kernel lives in /System/Library/Kernel

        run_command(
            [
                "grub-install",
                "--target=x86_64-efi",
                "--efi-directory=" + esp_mount,
                "--boot-directory="
                + os.path.join(target_mount, "System/Library/Kernel"),
                "--bootloader-id=MochiOS",
                "--removable",
                "--no-nvram",
            ]
        )

        grub_cfg_dir = os.path.join(target_mount, "System/Library/Kernel/grub")
        os.makedirs(grub_cfg_dir, exist_ok=True)

        grub_cfg = """set default=0
set timeout=5

insmod part_gpt
insmod fat
insmod ext2

menuentry "MochiOS" {
    search --no-floppy --set=root --label MOCHIOS_ROOT
    linux  /System/Library/Kernel/vmlinuz root=LABEL=MOCHIOS_ROOT rw quiet splash
    initrd /System/Library/Kernel/initrd.img
}
"""
        with open(os.path.join(grub_cfg_dir, "grub.cfg"), "w") as f:
            f.write(grub_cfg)


def finalize_installation(target_mount, esp_mount):
    with StatusBox("Cleanup", "Finalizing installation ..."):
        run_command(["umount", esp_mount])
        run_command(["umount", target_mount])
