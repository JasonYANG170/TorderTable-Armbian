#!/usr/bin/env python3
"""Exercise the real post-build growth commands on disposable GPT/ext4 images.

Run as root on Linux with gdisk, parted, e2fsprogs and loop devices available.
"""
import os
from pathlib import Path
import struct
import subprocess
import tempfile


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def partition(image):
    with image.open("rb") as disk:
        disk.seek(512)
        header = disk.read(92)
        assert header[:8] == b"EFI PART"
        backup = struct.unpack_from("<Q", header, 32)[0]
        last = struct.unpack_from("<Q", header, 48)[0]
        entries = struct.unpack_from("<Q", header, 72)[0]
        disk.seek(entries * 512)
        entry = disk.read(128)
        start, end = struct.unpack_from("<QQ", entry, 32)
        disk.seek(64 * 512)
        bootloader = disk.read(4096)
    return backup, last, start, end, entry[16:32], bootloader


source = Path(__file__).with_name("post-build.sh").read_text()
commands = source.split("# The desktop image is nearly full", 1)[1]
commands = commands[commands.index('if "$IS_DESKTOP"; then'):]
commands = commands.split("TMPDIR=$(mktemp -d)", 1)[0]
assert os.geteuid() == 0, "Run this test as root"

with tempfile.TemporaryDirectory(prefix="torder-growth-") as work:
    for variant in ("desktop", "console"):
        image = Path(work) / f"{variant}.img"
        run("truncate", "-s", "64M", str(image))
        run("sgdisk", "--clear", "--new=1:32768:0", "--typecode=1:8300", str(image))
        with image.open("r+b") as disk:
            disk.seek(64 * 512)
            disk.write(b"TORDER-SPL".ljust(4096, b"\xa5"))
        before = partition(image)
        loop = run("losetup", "-fP", "--show", str(image))
        try:
            run("mkfs.ext4", "-q", "-F", f"{loop}p1")
            uuid = run("blkid", "-s", "UUID", "-o", "value", f"{loop}p1")
        finally:
            run("losetup", "-d", loop)
        checks = r'''
test "$(blkid -s UUID -o value "${LOOP}p1")" = "$EXPECTED_UUID"
e2fsck -fn "${LOOP}p1"
BLOCK_COUNT=$(dumpe2fs -h "${LOOP}p1" 2>/dev/null | awk '/^Block count:/ {print $3}')
BLOCK_SIZE=$(dumpe2fs -h "${LOOP}p1" 2>/dev/null | awk '/^Block size:/ {print $3}')
PARTITION_SIZE=$(blockdev --getsize64 "${LOOP}p1")
test "$((PARTITION_SIZE / BLOCK_SIZE))" -eq "$BLOCK_COUNT"
'''
        subprocess.run(
            ["bash", "-euo", "pipefail", "-c",
             'LOOP=""; trap \'[ -z "$LOOP" ] || losetup -d "$LOOP"\' EXIT\n' + commands + checks],
            env={**os.environ, "IMG": str(image), "IS_DESKTOP": str(variant == "desktop").lower(),
                 "IMAGE_GROWTH_MIB": "32", "EXPECTED_UUID": uuid}, check=True,
        )
        after = partition(image)
        assert after[2] == before[2], "Root partition start moved"
        assert after[4:] == before[4:], "Partition GUID or SPL data changed"
        assert after[0] == image.stat().st_size // 512 - 1, "Backup GPT is not at EOF"
        assert after[3] == after[1], "Root partition does not reach the last usable sector"
        if variant == "desktop":
            assert image.stat().st_size == 96 * 1024 * 1024
            assert after[3] > before[3]
        else:
            assert image.stat().st_size == 64 * 1024 * 1024
            assert after == before
        assert "No problems found" in run("sgdisk", "--verify", str(image))
        print(f"PASS: {variant} image geometry, ext4 size, UUID and SPL data")
