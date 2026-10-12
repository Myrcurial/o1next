#!/usr/bin/env python3
"""o1raw2imd.py -- wrap a raw Osborne 1 SD sector image in an ImageDisk (.imd).

WHY THIS EXISTS
    #178 needs `MD10.COM` -- the MD-10 drive-table editor -- *run*, because the
    byte-to-field mapping of an 11-byte `DRIVETBL.DAT` record can be settled by
    editing one field and diffing the file. `MD10.COM` lives on the archive's
    Osborne single-density utilities disks, which are held as bare 100 KiB raw
    sector images (`research/adaptec/*.img`) with no container, and MAME will
    not open those. `imdmake.py` writes *blank* IMDs and `imdinfo.py` reads
    them; nothing wrapped a raw image. This is that half.

    The convention is the one the archive's own IMDs use (DRIVE_C.IMD,
    OCC1_HARDDISK.IMD): the raw image is in *physical* track order and the
    sector at file position p carries R = p+1, so the numbering map is the
    identity 1..10. CP/M's logical sector L then lands on R = skewtab[L]+1 --
    the Osborne 2:1 interleave -- which is exactly why `cpmfs.py` needs
    `skew 2` on these images. Checked by booting the result: `DIR` lists the
    same files `cpmfs.py` does and `MD10.COM` loads and runs. See
    docs/harddisk-decision.md 7.2 and #178.

USAGE
    o1raw2imd.py IN.img OUT.imd [--comment TEXT]

    Input must be 40 x 10 x 256 B FM, single-sided (102400 bytes). The DD
    images in the archive are already IMD, so there is no --dd path here.
"""
import sys
import time

SECTRK, SECLEN, CYLS = 10, 256, 40
SIZE = 102400
MODE_FM_250 = 2
SSIZE_256 = 1


def build(raw, comment, date):
    if len(raw) != SIZE:
        sys.exit(f"o1raw2imd.py: expected {SIZE} bytes, got {len(raw)}")
    # disk-analyse refuses a file that does not start with an IMD version line.
    out = bytearray()
    for line in [f"IMD 1.16: {date}"] + comment.splitlines():
        out += line.encode("latin-1") + b"\r\n"
    out += b"\x1a"
    for cyl in range(CYLS):
        out += bytes([MODE_FM_250, cyl, 0x00, SECTRK, SSIZE_256])
        out += bytes(range(1, SECTRK + 1))          # numbering map R=1..10
        for sec in range(SECTRK):
            off = (cyl * SECTRK + sec) * SECLEN
            out += b"\x01" + raw[off:off + SECLEN]  # type 1 = normal data
    return bytes(out)


def main(argv):
    args = list(argv)
    if len(args) < 2:
        sys.exit(__doc__)
    src, dst = args.pop(0), args.pop(0)
    comment, date = None, time.strftime("%d/%m/%Y %H:%M:%S")
    while args:
        a = args.pop(0)
        if a == "--comment":
            comment = args.pop(0)
        elif a == "--date":
            date = args.pop(0)
        else:
            sys.exit(f"o1raw2imd.py: unknown option {a!r}\n{__doc__}")
    if comment is None:
        comment = f"wrapped from {src} by o1raw2imd.py (#178)"
    data = build(open(src, "rb").read(), comment, date)
    open(dst, "wb").write(data)
    print(f"wrote {dst}: {len(data)} bytes, 250k FM {CYLS}x{SECTRK}x{SECLEN}")


if __name__ == "__main__":
    main(sys.argv[1:])
