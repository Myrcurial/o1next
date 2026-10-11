#!/usr/bin/env python3
"""imdmake.py -- write a blank Osborne 1 floppy image in ImageDisk (.imd) form.

WHY THIS EXISTS
    #95 asks whether the double-density upgrade really is a multi-format
    controller, and the acceptance test is "format a diskette, copy files on and
    off it, read it back". That needs *blank* disks to start from. The repo had
    a reader (`imdinfo.py`) and the archive had boot disks, but nothing that
    *makes* an image, and `disk-analyse` will not import a bare raw `.img`
    without a named format descriptor for the machine.

    So this is the writer half of `imdinfo.py`: it emits the two geometries the
    Osborne 1 actually used, in the same sector order MAME and the archive
    images use, filled with 0xE5 (the CP/M "unused/deleted" byte). The image
    boots nowhere on its own -- it is a formatted-but-empty diskette, which is
    what you want in the second drive (`-flop2`) when you are about to FORMAT or
    PIP onto it.

    It is deliberately stdlib-only and dependency-free: an IMD file is a text
    header, a 0x1A, then one self-describing record per track.

GEOMETRIES
    --dd  (default) Osborne 1 double density: 250 kbit/s MFM, 40 cylinders,
          1 head, 5 x 1024-byte sectors, R=1..5.  200 KiB formatted.
    --sd            Osborne 1 single density: 250 kbit/s FM,  40 cylinders,
          1 head, 10 x 256-byte sectors, R=1..10.  100 KiB formatted.

USAGE
    imdmake.py OUT.imd [--dd|--sd] [--comment TEXT] [--fill 0xE5]

Issue: #95 (see docs/dd-upgrade-formats.md).
"""
import sys
import time

MODES = {"fm": 2, "mfm": 5}          # 250 kbit/s FM / MFM
SSIZE = {128: 0, 256: 1, 512: 2, 1024: 3}
# geometry preset -> (mode, cylinders, sectors/track, sector size)
GEOM = {
    "dd": ("mfm", 40, 5, 1024),
    "sd": ("fm", 40, 10, 256),
}


def build(mode, cyls, spt, size, fill, comment, date):
    # The first header line must be "IMD <ver>: <date>" -- disk-analyse (Keir
    # Fraser) refuses a file that does not start that way, even though the track
    # records themselves are self-describing. Everything after it is free text.
    hdr = [f"IMD 1.16: {date}"] + (comment.splitlines() if comment else [])
    out = bytearray()
    for line in hdr:
        out += line.encode("latin-1") + b"\r\n"
    out += b"\x1a"
    ssize = SSIZE[size]
    for cyl in range(cyls):
        out += bytes([MODES[mode], cyl, 0x00, spt, ssize])
        out += bytes(range(1, spt + 1))          # sector numbering map R=1..spt
        for _ in range(spt):
            out += b"\x01" + bytes([fill]) * size  # type 1 = normal data
    return bytes(out)


def main(argv):
    args = list(argv)
    if not args:
        sys.exit(__doc__)
    out = args.pop(0)
    geom, comment, fill, date = "dd", None, 0xE5, time.strftime("%d/%m/%Y %H:%M:%S")
    while args:
        a = args.pop(0)
        if a in ("--dd", "--sd"):
            geom = a[2:]
        elif a == "--comment":
            comment = args.pop(0)
        elif a == "--fill":
            fill = int(args.pop(0), 0)
        elif a == "--date":
            date = args.pop(0)
        else:
            sys.exit(f"imdmake.py: unknown option {a!r}\n{__doc__}")
    mode, cyls, spt, size = GEOM[geom]
    if comment is None:
        comment = (f"Osborne 1 {'double' if geom == 'dd' else 'single'} density "
                   f"blank -- imdmake.py (#95)")
    data = build(mode, cyls, spt, size, fill, comment, date)
    with open(out, "wb") as f:
        f.write(data)
    print(f"wrote {out}: {len(data)} bytes, "
          f"{mode.upper()} {cyls}x{spt}x{size} ({cyls*spt*size//1024} KiB)")


if __name__ == "__main__":
    main(sys.argv[1:])
