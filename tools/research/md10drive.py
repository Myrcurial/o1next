#!/usr/bin/env python3
"""md10drive.py -- build a *bootable* MD-10 hard disk, byte-wise.

WHY THIS EXISTS
    #179's acceptance is "the period MD-10 software runs against it and boots
    CP/M from the emulated hard disk".  The drive has to *already* carry an
    MD-10 operating system, and the archive holds none -- that is what this
    supplies.

    The system was not synthesised by guesswork and not written by this tool: it
    is the output of the vendor's own installer.  `PREP.COM` (option 3,
    "Configure operating system") reads `HARDCCP.SPR`/`HARDBDOS.SPR` from the
    utilities disk, relocates them, and writes them to the drive -- it reports
    "Relocating operating system... Writing operating system... Operating system
    configuration complete".  The result is captured as the two artifacts in
    `research/adaptec/md10-system/`, and this tool lays them onto a fresh drive.
    The recipe that produced them is in `docs/md10-system.md`.

    What a bootable MD-10 drive contains (measured, not assumed):

        LBA 0        the disk label: 'M','D' at +0, the label text at +14,
                     the partition table from +48 (28-byte records)
        LBA 1..3     the rest of the four-block header (the 6C fill here)
        LBA 4        a table, carried in the layout's header artifact
        LBA 5..15    the operating system: 11 blocks (0x1600 bytes) that
                     HARD.COM's BIOS reads to 0xC200 and jumps into
        the rest     the 6C fill, except the first 64 blocks of each partition,
                     which the partition initialiser filled with E5 -- CP/M's
                     empty directory

    So a bootable drive is the layout's header + its E5 directory areas + a 6C
    fill, and that is what this writes: 8 KiB of artifact rather than a 23 MB
    blob.

USAGE
    tools/research/md10drive.py --out /tmp/md10/hd.chd            # a CHD for MAME
    tools/research/md10drive.py --out /tmp/md10/hd.raw --raw      # a raw image
    tools/research/md10drive.py --out ... --layout md10           # the PYXIS13 two-partition drive
    tools/research/md10drive.py --out ... --chs 306,4,17          # another geometry
    tools/research/md10drive.py --out ... --label MD10SYS         # a different label

    --layout picks which captured drive to reproduce, and each layout carries
    its own geometry, so --chs is only needed to override one:

      md20 (default)  PYXIS27, THREE partitions of 15399 blocks at LBA 20 /
                      15419 / 30818.  This is the driver's own static fallback
                      table, and the only layout whose partitions match the
                      shared DPB (DSM=1923 -> 7.5 MiB usable).  **Floor pin.**
                      Its O/S is already at its load base -- no relocation.
      md10            PYXIS13, two partitions of 11544 blocks.  The capture the
                      docs originally used.  Its O/S is relocated 0x100 high,
                      so it needs `md10reloc.py` first (#198), and its
                      partitions are smaller than the DPB claims, so it is not
                      safe to write to.

    `--label` re-stamps the label; the partition table and the O/S image are the
    captured ones.

    --os lays a *different* operating system.  It is only needed for the `md10`
    layout, whose captured `md10-os.bin` sits 0x100 above the address `HARD.COM`
    loads it at -- its `JP COMMAND` lands mid-instruction -- so a bootable drive
    needs the re-relocated image.  See docs/md10-system.md.

    Building a *new* geometry needs MAME, the archive's utilities disk and
    `PREP.COM`; `tools/research/md10prep.sh` drives that and this tool lays the
    result down.  See `docs/md10-system.md`.
"""
import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(HERE, "..", "..", "research", "adaptec", "md10-system")

CHS_DEFAULT = (321, 4, 18)
SECTOR_DEFAULT = 512
FILL_DEFAULT = 0x6C
LBA0_15 = os.path.join(ART, "lba0-15.bin")
OS_IMAGE = os.path.join(ART, "md10-os.bin")
# Where the partition initialiser put CP/M's empty directory (0xE5), and how
# many blocks of it -- measured off the captured drive (docs/md10-system.md).
DIRS = ((20, 64), (11564, 64))
E5 = 0xE5

# The captured layouts.  Each is a pair of committed artifacts plus the
# geometry and the partition initialiser's E5 directory regions -- measured off
# the drive, never synthesised (docs/md10-system.md).
#
#   md10  PYXIS13, TWO partitions of 11544 blocks.  The capture the docs
#         originally used.  Its O/S is relocated 0x100 high, so it needs
#         `md10reloc.py` before it will boot (#198) -- and its partitions are
#         smaller than the driver's shared DPB claims, so it is not safe to
#         write to.
#   md20  PYXIS27, THREE partitions of 15399 blocks at LBA 20 / 15419 / 30818.
#         This is the driver's *own static fallback table*, and the only layout
#         whose partitions match the shared DPB (DSM=1923 -> 7.5 MiB usable).
#         **This is the floor pin.**  Its O/S is already at its load base, so no
#         relocation step is needed.
LAYOUTS = {
    "md10": {
        "head": "lba0-15.bin",
        "os": "md10-os.bin",
        "chs": (321, 4, 18),
        "dirs": ((20, 64), (11564, 64)),
        "reloc": True,
    },
    "md20": {
        "head": "lba0-15-p27.bin",
        "os": "md10-os-p27.bin",
        "chs": (321, 8, 18),
        "dirs": ((20, 64), (15419, 64), (30818, 64)),
        "reloc": False,
    },
}
LAYOUT_DEFAULT = "md20"


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


def build(args):
    layout = LAYOUTS[args.layout]
    with open(os.path.join(ART, layout["head"]), "rb") as f:
        head = f.read()
    with open(args.os or os.path.join(ART, layout["os"]), "rb") as f:
        osimg = f.read()

    if args.chs is None:
        cyls, heads, spt = layout["chs"]
    else:
        cyls, heads, spt = (int(x) for x in args.chs.split(","))
    total = cyls * heads * spt
    if total * args.sectorsize < 16 * args.sectorsize + len(osimg):
        sys.exit("md10drive.py: geometry too small for the header and the O/S")

    image = bytearray([FILL_DEFAULT]) * (total * args.sectorsize)
    image[0:len(head)] = head
    # the O/S image is LBA 5..15, i.e. offset 5*sectorsize inside lba0-15.bin
    image[5 * args.sectorsize:5 * args.sectorsize + len(osimg)] = osimg
    for start, count in layout["dirs"]:
        if start + count > total:
            continue
        off = start * args.sectorsize
        image[off:off + count * args.sectorsize] = bytes([E5]) * (count * args.sectorsize)

    if args.label:
        lab = args.label.encode()[:11]
        off = 14
        image[off:off + 11] = lab + b"\x00" * (11 - len(lab))

    if args.raw:
        with open(args.out, "wb") as f:
            f.write(image)
        print("wrote %s: %d bytes, %d blocks (raw)" % (args.out, len(image), total))
        return 0

    chdman = find_chdman(args.chdman)
    if not chdman:
        sys.exit("md10drive.py: no chdman; set --chdman or $CHDMAN (REQUIREMENTS.md)")
    raw = args.out + ".raw"
    with open(raw, "wb") as f:
        f.write(image)
    if args.keep_raw:
        shutil.copyfile(raw, args.keep_raw)
    cmd = [chdman, "createhd", "-i", raw, "-o", args.out, "-c", "none",
           "-chs", "%d,%d,%d" % (cyls, heads, spt), "-ss", str(args.sectorsize)]
    if args.force:
        cmd.append("-f")
    print("$ " + " ".join(cmd))
    rc = subprocess.call(cmd)
    os.unlink(raw)
    if rc != 0:
        return rc
    print("wrote %s: %d blocks, %d/%d/%d x %d" %
          (args.out, total, cyls, heads, spt, args.sectorsize))
    return 0


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", required=True, help="the image to write")
    p.add_argument("--layout", default=LAYOUT_DEFAULT, choices=sorted(LAYOUTS),
                   help="which captured layout to build (default %s: the "
                        "three-partition PYXIS27, the floor pin)"
                        % LAYOUT_DEFAULT)
    p.add_argument("--chs", default=None,
                   help="cylinders,heads,sectors-per-track (default: the "
                        "layout's own geometry)")
    p.add_argument("--sectorsize", type=int, default=SECTOR_DEFAULT)
    p.add_argument("--label", default=None, metavar="TEXT",
                   help="re-stamp the disk label (default: the captured one)")
    p.add_argument("--os", default=None, metavar="PATH",
                   help="the O/S image to lay at LBA 5 (default: the layout's "
                        "own artifact)")
    p.add_argument("--raw", action="store_true", help="write a raw image, not a CHD")
    p.add_argument("--chdman", default=None, help="path to chdman")
    p.add_argument("--keep-raw", metavar="PATH", default=None)
    p.add_argument("--force", action="store_true")
    args = p.parse_args(argv[1:])
    if not args.force and not args.raw and os.path.exists(args.out):
        sys.exit("md10drive.py: %s exists (--force to overwrite)" % args.out)
    return build(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

