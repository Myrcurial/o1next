#!/usr/bin/env python3
"""md10table.py -- read the MD-10 disk label and partition table out of a drive.

WHY THIS EXISTS
    `docs/md10-system.md` describes a configured MD-10 drive by its label, its
    28-byte partition records and the `E5h` directory regions the partition
    initialiser writes.  Every one of those was read out by hand, twice, with a
    throwaway script -- once to capture the two-partition PYXIS13 drive and
    again to capture the three-partition PYXIS27 one (#247).  This is that
    script, so the readback is a command rather than a habit.

    It is the *verification* half of the repeatable geometry capability:
    `tools/research/md10prep.sh` drives the archive's own `PREP.COM` against a
    new geometry, and this says what the installer actually wrote.

WHAT IT READS
    LBA 0   the disk label -- 'M','D' at +0, the label text at +14, and the
            partition table from +48 as 28-byte records: a flag byte, a
            little-endian 24-bit start, a little-endian 16-bit length in
            512-byte blocks, ten bytes, then a ten-byte name.  The walk stops
            on a first byte of FFh, which is the terminator (PREP.COM writes it
            with the label, not with the partition -- docs/md10-system.md 2).
    LBA 4   the runtime table: the partition geometry again, then the per-drive
            type bytes the driver's SELDSK indexes (docs/md10-system.md 3).
    LBA 5+  the operating system, 11 blocks, which HARD.COM's BIOS reads to
            0xC200 and jumps into.

    `E5h` regions are reported because that is how the initialiser's work is
    visible: the first 64 blocks of each partition are CP/M's empty directory.

USAGE
    tools/research/md10table.py /tmp/md10/hd.raw
    tools/research/md10table.py /tmp/md10/hd.chd          # chdman extracts it
    tools/research/md10table.py /tmp/md10/hd.chd --json

    A CHD is extracted with `chdman extracthd` to a temporary file and removed
    afterwards; `--chdman` or $CHDMAN names the binary (REQUIREMENTS.md).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

BLOCK = 512
LABEL_PARTITIONS_OFF = 48
RECORD_LEN = 28
E5 = 0xE5


def find_chdman(explicit):
    if explicit:
        return explicit
    env = os.environ.get("CHDMAN")
    if env:
        return env
    found = shutil.which("chdman")
    if found:
        return found
    for cand in ("/Volumes/4TB/Users/jarlen/scratch/mame-mame0289/chdman",):
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return None


def load_image(path, chdman_arg):
    """The image's bytes, plus the path to use in messages."""
    with open(path, "rb") as f:
        magic = f.read(8)
    if magic[:8] == b"MComprHD":
        chdman = find_chdman(chdman_arg)
        if not chdman:
            sys.exit("md10table.py: %s is a CHD and there is no chdman; set "
                     "--chdman or $CHDMAN (REQUIREMENTS.md)" % path)
        tmp = tempfile.NamedTemporaryFile(suffix=".raw", delete=False)
        tmp.close()
        try:
            subprocess.check_call([chdman, "extracthd", "-i", path, "-o", tmp.name,
                                   "-f"], stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
            with open(tmp.name, "rb") as f:
                return f.read(), path
        finally:
            os.unlink(tmp.name)
    with open(path, "rb") as f:
        return f.read(), path

def parse_label(label):
    """The partition records in LBA 0, and whether the FFh terminator was found."""
    records = []
    i = LABEL_PARTITIONS_OFF
    terminated = False
    while i + RECORD_LEN <= len(label):
        r = label[i:i + RECORD_LEN]
        if r[0] == 0xFF:
            terminated = True
            break
        records.append({
            "flag": r[0],
            "start": r[1] | (r[2] << 8) | (r[3] << 16),
            "blocks": r[4] | (r[5] << 8),
            "name": r[16:16 + 10].split(b"\x00")[0].decode("latin1"),
        })
        i += RECORD_LEN
    for rec in records:
        rec["end"] = rec["start"] + rec["blocks"]
    return records, terminated


def e5_regions(data):
    """Every run of blocks whose first 64 bytes are all E5h."""
    regions = []
    start = None
    for b in range(len(data) // BLOCK):
        hit = data[b * BLOCK:b * BLOCK + 64] == bytes([E5]) * 64
        if hit and start is None:
            start = b
        elif not hit and start is not None:
            regions.append((start, b - 1))
            start = None
    if start is not None:
        regions.append((start, len(data) // BLOCK - 1))
    return regions


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("image", help="a raw drive image or a CHD")
    p.add_argument("--chdman", default=None, help="path to chdman")
    p.add_argument("--json", action="store_true", help="machine-readable output")
    args = p.parse_args(argv[1:])

    data, shown = load_image(args.image, args.chdman)
    label = data[:BLOCK]
    records, terminated = parse_label(label)
    lba4 = data[4 * BLOCK:4 * BLOCK + 32]
    regions = e5_regions(data)

    if args.json:
        print(json.dumps({
            "image": shown,
            "bytes": len(data),
            "blocks": len(data) // BLOCK,
            "label": {
                "magic": label[:2].decode("latin1"),
                "text": label[14:28].split(b"\x00")[0].decode("latin1"),
            },
            "partitions": records,
            "terminated": terminated,
            "lba4": lba4.hex(),
            "e5_regions": regions,
        }, indent=2))
        return 0

    print("%s: %d bytes, %d blocks" % (shown, len(data), len(data) // BLOCK))
    print("label: magic %r  text %r" %
          (label[:2].decode("latin1"),
           label[14:28].split(b"\x00")[0].decode("latin1")))
    print("partition table (from +%d, %d-byte records):" %
          (LABEL_PARTITIONS_OFF, RECORD_LEN))
    if not records:
        print("  (none)")
    for n, rec in enumerate(records):
        print("  %d  flag=%02X  start=%-6d  blocks=%-6d  end=%-6d  %s" %
              (n, rec["flag"], rec["start"], rec["blocks"], rec["end"],
               rec["name"] or "-"))
    if not terminated:
        print("  WARNING: no FFh terminator in LBA 0 -- the walker at 0x23E6 "
              "would run off the end of the table (docs/md10-system.md 2)")
    print("LBA 4 (the runtime table): %s" % lba4.hex(" "))
    print("E5h regions (CP/M empty directories): %s" %
          (", ".join("%d-%d" % r for r in regions) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

