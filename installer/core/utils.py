import json
import subprocess
import sys

from .tui import confirm as _tui_confirm
from .tui import menu_select as _tui_menu_select


def run_command(cmd, shell=False, check=True, capture_output=True):
    try:
        result = subprocess.run(
            cmd, shell=shell, check=check, capture_output=capture_output, text=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        if check:
            from .tui import show_message

            show_message(
                "Command Error",
                f"Error running command: {cmd}\nOutput: {e.stdout}\nError: {e.stderr}",
            )
            sys.exit(1)
        return None


def get_disks():
    output = run_command(
        ["lsblk", "--json", "-p", "-o", "NAME,SIZE,TYPE,MOUNTPOINT,MODEL"]
    )
    if not output:
        return []
    data = json.loads(output)
    disks = [d for d in data.get("blockdevices", []) if d["type"] == "disk"]
    return disks


def clear_screen():
    pass


def menu_select(options, title="Select an option"):
    return _tui_menu_select(options, title=title)


def confirm(prompt):
    return _tui_confirm("Confirmation", prompt)
