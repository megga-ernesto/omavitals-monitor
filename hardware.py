"""Read hardware details for the dashboard using local Linux interfaces."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from metrics import SYS, MIB, number, read


def fields(path, separator="="):
    return dict((key.strip(), value.strip())
                for line in read(path).splitlines()
                if separator in line
                for key, value in [line.split(separator, 1)])


def device_model(card):
    address = (card / "device").resolve().name
    if shutil.which("lspci") and re.fullmatch(r"[\da-f]{4}:[\da-f]{2}:[\da-f]{2}\.\d", address):
        try:
            output = subprocess.check_output(["lspci", "-s", address, "-mm"],
                                             text=True, timeout=0.6)
            labels = re.findall(r'"([^"]*)"', output)
            if len(labels) >= 3:
                return " ".join(labels[1:3])
        except (OSError, subprocess.SubprocessError):
            pass
    return fields(card / "device/uevent").get("PCI_ID", card.name)


def collect():
    cpu = fields("/proc/cpuinfo", ":")
    gpu = []
    for card in sorted((SYS / "class/drm").glob("card[0-9]*")):
        if not re.fullmatch(r"card\d+", card.name):
            continue
        device = card / "device"
        gpu.append([device_model(card), (device / "driver").resolve().name if (device / "driver").exists() else "",
                    number(device / "mem_info_vram_total")])
    disks = []
    for disk in sorted((SYS / "block").iterdir()):
        if not (disk / "device").exists() or re.search(r"(boot\d+|rpmb)$", disk.name):
            continue
        model = read(disk / "device/model").strip() or read(disk / "device/name").strip()
        disks.append([disk.name, model, (number(disk / "size") or 0) * 512])
    interfaces = sorted(path.name for path in (SYS / "class/net").iterdir()
                        if path.name != "lo" and read(path / "operstate").strip() in {"up", "unknown"})
    batteries = []
    for path in (SYS / "class/power_supply").glob("*"):
        if read(path / "type").strip() != "Battery" or number(path / "present") == 0:
            continue
        model = read(path / "model_name").strip()
        health = None
        for unit in ("energy", "charge"):
            full, design = number(path / (unit + "_full")), number(path / (unit + "_full_design"))
            if full is not None and design:
                health = round(100 * full / design)
                break
        batteries.append([model or path.name, health])
    root_fs = ""
    for line in read("/proc/self/mountinfo").splitlines():
        left, _, right = line.partition(" - ")
        if len(left.split()) >= 5 and left.split()[4] == "/" and right:
            root_fs = right.split()[0]
    zram = []
    for device in sorted((SYS / "block").glob("zram*")):
        algorithms = read(device / "comp_algorithm")
        selected = re.search(r"\[([^\]]+)\]", algorithms)
        zram.append([device.name, selected[1] if selected else "", (number(device / "disksize") or 0) / MIB])
    swap = [Path(line.split()[0]).name for line in read("/proc/swaps").splitlines()[1:] if line.split()]
    return {"cpu": [cpu.get("model name") or cpu.get("Hardware") or cpu.get("Processor") or os.uname().machine,
                    os.cpu_count() or 1],
            "gpu": gpu[:8], "disk": disks[:12], "network": interfaces[:16],
            "battery": batteries[:8], "storage": root_fs, "zram": zram[:8], "swap": swap[:12]}


if __name__ == "__main__":
    print(json.dumps(collect()))
