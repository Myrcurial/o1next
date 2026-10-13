#!/usr/bin/env python3
"""o1raw2imd.py -- wrap a raw Osborne 1 sector image in an ImageDisk (.imd).

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

    The `--dd` path was added for #203. The 1.44 ROM reassembly has to hand the
    vendor's ACT assembler a CP/M disk carrying `rom144.asm`, and the only
    toolchain here that writes a CP/M filesystem is `cpmtools` -- which reads
    and writes *raw* sector images, not IMD. `mkfs.cpm`/`cpmcp` build the
    volume, this wraps it, and MAME can then mount it. The archive's DD images
    are already IMD, so nothing in the archive needed this before; a *new* DD
    volume did.

USAGE
    o1raw2imd.py IN.img OUT.imd [--comment TEXT]
    o1raw2imd.py --dd IN.img OUT.imd [--comment TEXT]

    SD (default) input must be 40 x 10 x 256 B FM, single-sided (102400 bytes);
    `--dd` input must be 40 x 5 x 1024 B MFM, single-sided (204800 bytes) --
    the format `imdmake.py --dd` writes blank and `cpmtools`' `osborne1`
    diskdef describes (`docs/mame-emulation.md` section 4). Both are 1:1
    numbered, so the numbering map is the identity in each case.
"""
import sys
import time

# The two Osborne 1 floppy formats, as (sectors/track, bytes/sector, IMD mode
# byte, IMD sector-size byte, cylinders).  Modes: 2 = 250 kbps FM (SD),
# 5 = 250 kbps MFM (DD); sizes: 1 = 256 B, 3 = 1024 B.  See IMD.TXT section 6.
GEOM = {
    "sd": dict(sectrk=10, seclen=256, mode=2, ssize=1, cyls=40),
    "dd": dict(sectrk=5, seclen=1024, mode=5, ssize=3, cyls=40),
}


def build(raw, geom, comment, date):
    sectrk, seclen = geom["sectrk"], geom["seclen"]
    cyls = geom["cyls"]
    size = cyls * sectrk * seclen
    if len(raw) != size:
        sys.exit(f"o1raw2imd.py: expected {size} bytes, got {len(raw)}")
    # disk-analyse refuses a file that does not start with an IMD version line.
    out = bytearray()
    for line in [f"IMD 1.16: {date}"] + comment.splitlines():
        out += line.encode("latin-1") + b"\r\n"
    out += b"\x1a"
    for cyl in range(cyls):
        out += bytes([geom["mode"], cyl, 0x00, sectrk, geom["ssize"]])
        out += bytes(range(1, sectrk + 1))          # numbering map, R=1..N
        for sec in range(sectrk):
            off = (cyl * sectrk + sec) * seclen
            out += b"\x01" + raw[off:off + seclen]  # type 1 = normal data
    return bytes(out)


def main(argv):
    args = list(argv)
    if len(args) < 2:
        sys.exit(__doc__)
    fmt = "sd"
    if args and args[0] == "--dd":
        fmt, args = "dd", args[1:]
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
        comment = f"wrapped from {src} by o1raw2imd.py (#178 #203)"
    geom = GEOM[fmt]
    data = build(open(src, "rb").read(), geom, comment, date)
    open(dst, "wb").write(data)
    dens = "FM" if fmt == "sd" else "MFM"
    print(f"wrote {dst}: {len(data)} bytes, 250k {dens} "
          f"{geom['cyls']}x{geom['sectrk']}x{geom['seclen']}")


if __name__ == "__main__":
    main(sys.argv[1:])
