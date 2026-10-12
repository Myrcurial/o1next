#!/usr/bin/env python3
"""drivetbl.py -- read the whole MD-10 drive table out of DRIVETBL.DAT.

WHY THIS EXISTS
    #178's drive-table question was answered by reading the shipped
    `DRIVETBL.DAT`, and the file is not what its directory entry says it is.
    The directory gives `rc = 1` (128 bytes) while the file's blocks hold
    16 512 bytes of live data, so `cpmfs.py get` returns only the first 128 --
    the header and the first five name records. The rest of the file is only
    reachable by walking the block list, which is what this does.

    The structure it reads (see docs/harddisk-decision.md 7.2):

        0x0000  13-byte header
                  +0..1  13 + 11*N, the end offset of the name table (LE)
                  +2     the next free description-record index
                  +3     13 -- the header length, i.e. where records start
        0x000D  N x 11-byte name records: a NUL-padded name (up to 10 chars)
                followed by one byte -- the index of that drive's description
                record
        then    9 bytes: 00 "RDBAK" 00 00 00, the end-of-table sentinel (its
                leading 0x00 is what stops the driver's name search)
        then    one 128-byte description record per index -- and the index is
                the CP/M *record number*, so index N lives at file offset
                128*N, the first being 16 (offset 2048), which is why records
                11..15 of the file are a gap between the two areas:
                  +0..1 cylinders (LE)      +5..6 write precomp (LE)
                  +2    heads               +7    landing zone
                  +3..4 reduced write       +8    step code
                        current (LE)
                followed by the free-text description, NUL-terminated, with
                the stale tails of longer earlier strings left behind.

USAGE
    drivetbl.py IMAGE [--md]      IMAGE is raw or .imd (see --imd note below)
    --md   emit a Markdown table instead of a human-readable one

    The image must be the raw 40x10x256B FM single-density form. MAME writes
    .imd back, so de-wrap one first:
        tools/research/imdinfo.py --raw out.img in.imd

Issue: #178.
"""
import sys

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
sys.path.insert(0, __import__("os").path.join(
    __import__("os").path.dirname(__import__("os").path.abspath(__file__)), ".."))
from cpmfs import CPM                                    # noqa: E402

HEADER = 13
RECLEN = 11
DESC_FIRST = 16                                          # first description index
DESC_LEN = 128
SECTORS_PER_TRACK = 18                                   # the editor's Cap= formula
SECTOR_BYTES = 512


def load(path, fmt="osb1sssd"):
    fs = CPM(path, fmt)
    ent = [e for e in fs.entries
           if e["name"].rstrip() == "DRIVETBL" and e["ext"].rstrip() == "DAT"]
    if not ent:
        sys.exit("drivetbl.py: no DRIVETBL.DAT in this image")
    data = bytearray()
    for b in ent[0]["blocks"]:
        if b:
            data += fs.block_bytes(b)
    return bytes(data)


def parse(data):
    end = data[0] | (data[1] << 8)
    n = (end - HEADER) // RECLEN
    names = []
    for i in range(n):
        base = HEADER + RECLEN * i
        rec = data[base:base + RECLEN]
        raw = rec[:10].split(b"\x00")[0]
        # The driver's name search does `AND 7Fh` on the record's first byte,
        # so bit 7 of a name's first character is a flag, not text.
        flag = "*" if raw[:1] and raw[0] & 0x80 else ""
        name = (bytes([raw[0] & 0x7F]) + raw[1:]).decode("latin-1") if raw else ""
        names.append((name + flag, rec[10]))
    # The header's byte 2 is the next *free* description index, so the used
    # ones are DESC_FIRST .. that-1, and index N sits at file offset 128*N.
    descs = {}
    for idx in range(DESC_FIRST, data[2]):
        base = DESC_LEN * idx
        rec = data[base:base + DESC_LEN]
        p = rec[:9]
        cyl = p[0] | (p[1] << 8)
        rwc = p[3] | (p[4] << 8)
        pre = p[5] | (p[6] << 8)
        descs[idx] = (cyl, p[2], rwc, pre, p[7], p[8],
                      rec[9:].split(b"\x00")[0].decode("latin-1"))
    return end, names, descs


def main(argv):
    args = list(argv)
    md = "--md" in args
    args = [a for a in args if a != "--md"]
    if not args:
        sys.exit(__doc__)
    data = load(args[0])
    end, names, descs = parse(data)
    print(f"# DRIVETBL.DAT: {len(data)} bytes of blocks, "
          f"name-table end offset {end}, {len(names)} name records, "
          f"{len(descs)} description records", file=sys.stderr)
    if md:
        print("| Name | Cyl | Heads | RWC | LZ | Step | Cap | Description |")
        print("|---|---|---|---|---|---|---|---|")
    for name, idx in names:
        if idx not in descs:
            print(f"  {name:10s} -> index {idx} (missing!)")
            continue
        cyl, heads, rwc, pre, lz, step, desc = descs[idx]
        cap = cyl * heads * SECTORS_PER_TRACK * SECTOR_BYTES // 1024
        if md:
            print(f"| `{name}` | {cyl} | {heads} | {rwc} | {lz} | {step} "
                  f"| {cap}K | {desc} |")
        else:
            print(f"  {name:10s} idx={idx:3d}  cyl={cyl:5d} heads={heads:3d} "
                  f"rwc={rwc:5d} pre={pre:5d} lz={lz:3d} step={step}  "
                  f"cap={cap}K  {desc}")


if __name__ == "__main__":
    main(sys.argv[1:])
