import os

from .tui import StatusBox
from .utils import run_command


def set_hostname(target_mount, hostname):
    with StatusBox("Configuration", f"Setting hostname to {hostname}..."):
        hostname_path = os.path.join(target_mount, "etc/hostname")
        os.makedirs(os.path.dirname(hostname_path), exist_ok=True)
        with open(hostname_path, "w") as f:
            f.write(hostname + "\n")

        hosts_path = os.path.join(target_mount, "etc/hosts")
        with open(hosts_path, "w") as f:
            f.write("127.0.0.1 localhost\n")
            f.write(f"127.0.1.1 {hostname}\n")


def set_root_password(target_mount, password):
    # This is trickier as it needs to run in chroot or use a hashed password
    # For now, let's just use a simple method if possible
    with StatusBox("Configuration", "Setting root password..."):
        # Using 'chroot' to set password
        # passwd expects input from stdin
        run_command(
            f"echo 'root:{password}' | chroot {target_mount} chpasswd", shell=True
        )
