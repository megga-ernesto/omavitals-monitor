"""Collect bounded process counters from procfs without reading command arguments."""

import json
import os
from pathlib import Path
import sys
import time


def process_row(directory):
    try:
        stat = (directory / "stat").read_text(errors="replace")
        start = stat.index("(")
        end = stat.rindex(")")
        fields = stat[end + 2:].split()
        name = stat[start + 1:end][:96]
        try:
            executable = os.readlink(directory / "exe")[:512]
        except OSError:
            executable = ""
        try:
            io = dict(line.split(":", 1) for line in (directory / "io").read_text().splitlines())
            disk = int(io["read_bytes"]) + int(io["write_bytes"])
        except (OSError, ValueError, KeyError):
            disk = None
        return [int(directory.name), int(fields[1]), name, executable,
                fields[0], int(fields[19]), int(fields[11]) + int(fields[12]),
                max(0, int(fields[21])), disk]
    except (OSError, ValueError, IndexError):
        return None


def snapshot(proc=Path("/proc")):
    rows = []
    truncated = False
    for directory in proc.iterdir():
        if not directory.name.isdecimal():
            continue
        row = process_row(directory)
        if row:
            if len(rows) >= 8192:
                truncated = True
                break
            rows.append(row)
    return {
        "now": time.monotonic(),
        "uptime": float((proc / "uptime").read_text().split()[0]),
        "ticks": os.sysconf("SC_CLK_TCK"),
        "pageSize": os.sysconf("SC_PAGE_SIZE"),
        "rows": rows,
        "truncated": truncated,
    }


if __name__ == "__main__":
    json.dump(snapshot(), sys.stdout, separators=(",", ":"))
