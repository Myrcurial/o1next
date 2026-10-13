#!/usr/bin/env python3
"""mkdrive.py -- build a blank-but-formatted ST-506/MFM hard disk image.

WHY THIS EXISTS
    The MD-10's own format utility cannot finish under MAME: the ACB-4000's
    FORMAT writes the drive's data fields (MAME's `SCSIHD` accepts the command
    and writes nothing), and the verify pass that follows it is SEARCH DATA
    EQUAL (2F hex), which `t10spc`/`t10sbc` do not implement at all -- so
    `PREP.COM`'s initialize runs to "Verifying disk (first pass)..." and loops
    there for ever.  See docs/osborne1ng-machine.md section 5.

    The *result* of a format is not a secret, so build it instead.  The ACB-4000
    manual (research/adaptec/acb4000/400003-00A_ACB-4000A_Users_Manual_Oct85.pdf,
    section 4.4.5 and the FORMAT command reference) says:

        The FORMAT command writes drive characteristics, ID and data fields
        onto the drive and writes a fill pattern into the user data field ...
        completely written with 6C hex unless otherwise specified in the
        format command.

    So a formatted-but-empty drive is every sector's data field full of 6C, and
    that is all this writes.  The drive's *characteristics* go in the ID fields,
    which a CHD does not model -- but `chdman`'s GDDD metadata is the same
    record (cylinders, heads, sectors, bytes/sector), which is why the geometry
    is passed to `chdman` rather than written into the data.

    That is the byte-wise blob: no 1984 tool required, and no dependency beyond
    `chdman` (REQUIREMENTS.md).

HOW IT IS DRIVEN
    tools/research/mkdrive.py --out /tmp/md10/hd.chd
    tools/research/mkdrive.py --out /tmp/md10/st412.chd --chs 306,4,17
    tools/research/mkdrive.py --out /tmp/md10/hd.chd --fill d9   # PREP asks d9
    tools/research/mkdrive.py --out /tmp/md10/hd.chd --label MD10  # recognisable

    --label writes the MD-10 disk label into LBA 0, which is what makes PREP.COM
    treat the drive as its own: without it, main-menu option 1 answers *"Disk has
    unrecognizable format (or none)"* and asks for a drive name before it will do
    anything.  The check is measured, not guessed -- READ CAPACITY must report
    512-byte blocks, a READ of LBA 0 must succeed, and the first two bytes of the
    label must be `MD` with the byte at +28 below 20h (docs/osborne1ng-machine.md
    section 6).  A drive built without --label is still a perfectly good *target*
    for the card; it just is not one PREP will initialise.

    --chs defaults to 321,4,18 -- PYXIS13, the entry MD10.COM offers a new
    drive, and the geometry docs/harddisk-decision.md section 7.2 recommends.
    Other geometries: that section's table, or the period list archived at
    research/adaptec/compatible-drives-1991-usenet.txt (which is the drive
    manufacturers' own numbering, so it says 320 where DRIVETBL.DAT says 321).

    --fill defaults to 6c, the manual's fill.  PREP.COM asks for a *unique* fill
    byte and sends d9 in the FORMAT CDB, so both are worth having.

    --chdman defaults to `chdman` on PATH, then to the one in a MAME source
    tree beside the machine if $CHDMAN says so.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

FILL_DEFAULT = 0x6C           # the ACB-4000 manual's default data fill
CHS_DEFAULT = (321, 4, 18)    # PYXIS13, from DRIVETBL.DAT
SECTOR_DEFAULT = 512

# The MD-10 disk label, as PREP.COM's recognisability check wants it.  That check
# is three tests, measured (docs/osborne1ng-machine.md 6): READ CAPACITY succeeds
# and reports 512-byte blocks; a READ of LBA 0 succeeds; and the first two bytes
# of what comes back are `MD`, with the byte at +28 below 20h.  So a drive is
# "recognisable" -- PREP offers its Disk initialization menu instead of "Disk has
# unrecognizable format (or none)" -- when LBA 0 carries this.
LABEL_SIG = b"MD"             # +0, the signature the check compares against
LABEL_TEXT_OFF = 14           # +14, where the label editor puts its text
LABEL_TEXT_MAX = 11           # ... and how much of it it accepts
LABEL_END_OFF = 48            # +48, the partition table's FFh terminator


def build_label(text):
    """The 512-byte disk label: signature, text at +14, FFh at +48."""
    lab = bytearray(SECTOR_DEFAULT)
    lab[0:len(LABEL_SIG)] = LABEL_SIG
    t = text.encode("latin-1")[:LABEL_TEXT_MAX]
    lab[LABEL_TEXT_OFF:LABEL_TEXT_OFF + len(t)] = t
    lab[LABEL_END_OFF] = 0xFF
    return bytes(lab)


def find_chdman(explicit):
    if explicit:
        return explicit
    env = os.environ.get("CHDMAN")
    if env:
        return env
    found = shutil.which("chdman")
    if found:
        return found
    sys.exit("mkdrive.py: no chdman; set --chdman or $CHDMAN (REQUIREMENTS.md)")


def main(argv):
    p = argparse.ArgumentParser(add_help=True, description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", required=True, help="the CHD to write")
    p.add_argument("--chs", default="%d,%d,%d" % CHS_DEFAULT,
                   help="cylinders,heads,sectors (default 321,4,18 = PYXIS13)")
    p.add_argument("--sectorsize", type=int, default=SECTOR_DEFAULT,
                   help="bytes per sector (default 512)")
    p.add_argument("--fill", default="%02x" % FILL_DEFAULT,
                   help="the data fill byte (default 6c, the manual's)")
    p.add_argument("--label", default=None, metavar="TEXT",
                   help="write the MD-10 disk label into LBA 0, so PREP.COM's "
                        "recognisability check passes (default: no label, which "
                        "PREP calls 'unrecognizable format')")
    p.add_argument("--chdman", default=None, help="path to chdman")
    p.add_argument("--keep-raw", metavar="PATH", default=None,
                   help="also write the raw image here, for inspection")
    p.add_argument("--force", action="store_true", help="overwrite the output")
    args = p.parse_args(argv)

    try:
        cyl, heads, sec = (int(x) for x in args.chs.split(","))
    except ValueError:
        sys.exit("mkdrive.py: --chs wants cylinders,heads,sectors")
    fill = int(args.fill, 16)
    if not 0 <= fill <= 0xFF:
        sys.exit("mkdrive.py: --fill wants a byte")
    if os.path.exists(args.out) and not args.force:
        sys.exit(f"mkdrive.py: {args.out} exists (--force to overwrite)")

    size = cyl * heads * sec * args.sectorsize
    print(f"geometry: {cyl}/{heads}/{sec} x {args.sectorsize} = {size:,} bytes "
          f"({size // 1024 // 1024} MB), fill {fill:02x}")

    chdman = find_chdman(args.chdman)
    raw = args.keep_raw or tempfile.mktemp(prefix="mkdrive.", suffix=".raw")
    try:
        with open(raw, "wb") as f:
            chunk = bytes([fill]) * (1 << 20)
            left = size
            while left > 0:
                n = min(left, len(chunk))
                f.write(chunk[:n])
                left -= n
            if args.label is not None:
                f.seek(0)
                f.write(build_label(args.label))
                print(f"label: {args.label!r} at LBA 0 (+14), "
                      f"signature {LABEL_SIG!r}, FF at +{LABEL_END_OFF}")

        cmd = [chdman, "createhd", "-i", raw, "-o", args.out, "-c", "none",
               "-chs", f"{cyl},{heads},{sec}", "-ss", str(args.sectorsize), "-f"]
        print("$ " + " ".join(cmd))
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL)
    finally:
        if not args.keep_raw:
            os.unlink(raw)

    info = subprocess.run([chdman, "info", "-i", args.out],
                          capture_output=True, text=True, check=True).stdout
    for line in info.splitlines():
        if any(k in line for k in ("Logical size", "Metadata", "CYLS")):
            print("  " + line.strip())
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
