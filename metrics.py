"""Read Linux resource counters. Output a single bounded JSON snapshot."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

SYS = Path("/sys")
MIB = 1024 ** 2
GIB = 1024 ** 3


def read(path):
    try:
        return Path(path).read_text()
    except OSError:
        return ""


def number(path):
    value = read(path).strip()
    return int(value) if value.isdecimal() else None


def memory():
    return {
        key: int(value.split()[0]) * 1024
        for key, value in (line.split(":", 1) for line in read("/proc/meminfo").splitlines())
        if key in {"MemTotal", "MemAvailable", "SwapTotal", "SwapFree"}
    }


def zram():
    devices = []
    for device in (SYS / "block").glob("zram*"):
        fields = read(device / "mm_stat").split()
        if len(fields) >= 3 and all(field.isdecimal() for field in fields[:3]):
            devices.append([int(fields[0]), int(fields[2])])
    if devices:
        return [sum(device[index] for device in devices) / MIB for index in range(2)]


def gpu(values):
    cards = [card for card in (SYS / "class/drm").glob("card*")
             if re.fullmatch(r"card\d+", card.name)]
    for card in sorted(cards):
        busy = number(card / "device/gpu_busy_percent")
        if busy is not None and busy <= 100:
            values["gpu"] = [busy, "%"]
            return
    nvidia = shutil.which("nvidia-smi")
    if nvidia:
        try:
            result = subprocess.run(
                [nvidia, "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
                capture_output=True, text=True, timeout=1, check=True,
            )
            loads = [int(line) for line in result.stdout.splitlines()
                     if line.strip().isdecimal() and int(line) <= 100]
            if loads:
                values["gpu"] = [loads[0], "%"]
                return
        except (OSError, subprocess.SubprocessError):
            pass
    for card in sorted(cards):
        for path in (card / "gt_act_freq_mhz", card / "gt_cur_freq_mhz",
                     card / "gt/gt0/rps_act_freq_mhz", card / "device/tile0/gt0/freq0/act_freq"):
            frequency = number(path)
            if frequency is not None:
                values["gpu"] = [frequency, "MHz"]
                return


def disks():
    for device in (SYS / "block").iterdir():
        if not (device / "device").exists() or re.search(r"(boot\d+|rpmb)$", device.name):
            continue
        fields = read(device / "stat").split()
        if len(fields) >= 7:
            yield device.name, [int(fields[2]) * 512, int(fields[6]) * 512]


def network():
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, counters = line.rsplit(":", 1)
        fields = counters.split()
        name = name.strip()
        if name != "lo" and len(fields) >= 9:
            yield name, [int(fields[0]), int(fields[8])]


def battery():
    capacities = [number(path / "capacity") for path in (SYS / "class/power_supply").glob("*")
                  if read(path / "type").strip() == "Battery" and number(path / "present") != 0]
    valid = [value for value in capacities if value is not None and 0 <= value <= 100]
    if valid:
        return [sum(valid) / len(valid), "%"]


def temperature():
    readings = [
        number(path)
        for monitor in (SYS / "class/hwmon").glob("*")
        if read(monitor / "name").strip() in {"coretemp", "k10temp", "zenpower", "cpu_thermal", "soc_thermal"}
        for path in monitor.glob("temp*_input")
    ]
    valid = [value for value in readings if value is not None and value <= 150000]
    if valid:
        return [max(valid) / 1000, "°C"]


def snapshot(enabled):
    values = {}
    counters = {}
    if "cpu" in enabled:
        fields = read("/proc/stat").partition("\n")[0].split()
        if len(fields) >= 9 and fields[0] == "cpu":
            times = [int(field) for field in fields[1:9]]
            counters["cpu"] = [sum(times), times[3] + times[4]]
    if "ram" in enabled or "swap" in enabled:
        info = memory()
        for key, total_key, free_key in (
            ("ram", "MemTotal", "MemAvailable"), ("swap", "SwapTotal", "SwapFree")
        ):
            if key in enabled and total_key in info and free_key in info:
                values[key] = [max(0, info[total_key] - info[free_key]) / GIB, info[total_key] / GIB]
    if "storage" in enabled:
        try:
            fs = os.statvfs("/")
            used = (fs.f_blocks - fs.f_bfree) * fs.f_frsize
            values["storage"] = [used / GIB, (used + fs.f_bavail * fs.f_frsize) / GIB]
        except OSError:
            pass
    for key, measure in (("zram", zram), ("battery", battery), ("temperature", temperature)):
        if key in enabled:
            values[key] = measure()
    for key, measure in (("disk", disks), ("network", network)):
        if key in enabled:
            counters[key] = dict(measure())
    if "gpu" in enabled:
        gpu(values)
    return {"time": time.monotonic(), "values": values, "counters": counters}


if __name__ == "__main__":
    print(json.dumps(snapshot(set(sys.argv[1:]))))
