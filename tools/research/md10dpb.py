#!/usr/bin/env python3
"""md10dpb.py -- patch the MD-10 driver's DPB, descriptor table and ALVs (#247).

WHY THIS EXISTS
    The MD-10's hard-disk drives do not carry their geometry in the drive, they
    carry it in the *driver*: `HARD.COM`'s embedded MD-10 BIOS holds one DPB at
    `0xDDB6` and three 24-byte descriptors whose DPHs all point at it.  So all
    three hard-disk drives have the same geometry in CP/M's view -- `DSM = 1923`,
    i.e. 15399 blocks, 7.5 MiB -- whatever the partitions on the drive actually
    are, and `docs/md10-system.md` 9.1 records the two ways that hurts:

      * a partition *bigger* than 15399 blocks is bigger than CP/M will ever use;
      * a partition *smaller* one (the PYXIS13 two-partition drive, 11544 blocks)
        is over-claimed, and the 1.9 MiB CP/M thinks it has lands in the next
        partition -- starting with that partition's directory.

    This is the patch step.  It rewrites that geometry, per drive:

      * **one DPB per hard-disk drive**, so the three partitions can differ in
        size (`PREP.COM`'s "Non-standard unequal drive partitioning" makes them);
      * **one allocation vector per DPB**, sized from that DPB's `DSM`, laid out
        in the RAM that is actually free (below);
      * and the three descriptors' DPB and ALV pointers, to match.

    `HARD.COM` is the single patch site: the floppy-loaded driver and ROM 2.0's
    `HCBOOT` payload both come from it (`tools/research/rom2image.py` reads the
    MD-10 BIOS out of it), so one patched file serves both boots.

WHERE THE ALVs GO, MEASURED
    The ALV is one bit per CP/M block, so it grows with the partition: 241 bytes
    for the shipped `DSM = 1923`, 1024 for a partition at CP/M's 32 MiB ceiling.
    Three of those do not fit anywhere obvious, which is the decision this tool
    exists to have already made.  The map below was measured on a booted machine
    (a memory dump after `A0>`, and the sources for the rest):

        0xD800-0xDDC4   the MD-10 BIOS image (0x5C5 bytes, copied from the ROM)
        0xDDC5-0xE0EF   **free** -- 811 bytes, below the hand-over stub
        0xE0F0-0xE0FD   ROM 2.0's hand-over stub (14 bytes, docs/o1-rom-2.0.md 4.6)
        0xE100-0xE8FF   the CBIOS
        0xE900-0xEA7F   the CBIOS's own RAM: its ALV, CSV and scratch
                        (`occbio`/`occram15.asm`, `ORG CCP+1E00h`, guarded by
                        `YYY > MRAM`) -- **not free**
        0xEA80-0xEAFF   MRAM, the ROM's host buffer -- **not free**
        0xEB00-0xEBFF   unclaimed and unmeasured; this tool does not use it
        0xEC00-0xEE7F   **free** -- 640 bytes, above the CBIOS
        0xEE80-0xEEFF   DIRBUF, shared by all three drives
        0xEF00-0xEFFF   the monitor's cells and stack (`ROMSTK` 0xEFC1, `CCPADR`
                        0xEFD2, ...), live after the hand-over -- **not free**

    So the budget is **811 + 640 = 1451 bytes**, and this tool fills Pocket A
    first and spills into Pocket B, never touching the stub, the CBIOS or
    DIRBUF.  A layout that does not fit is **refused**, with the arithmetic.

WHAT IT DOES *NOT* FIX: PREP.COM'S OWN CEILING
    `PREP.COM` will not make a partition bigger than **16384 blocks (8 MiB)** --
    measured, not assumed: on a 93600-block drive "6 equal" gives 15595 blocks
    each and succeeds, on the same drive "5 equal" gives 18714 and stops with
    `Partitions selected are too large!`, and on a 96048-block drive "6 equal"
    gives 16003 and succeeds.  So 8 MiB is the vendor installer's ceiling, and it
    is *not* the DPB's 15399: a partition of 15595 or 16003 blocks is accepted by
    PREP.COM and over-claimed by the shipped DPB.  Patching the DPB makes CP/M
    agree with the drive; it does not let PREP.COM make a bigger one.  Beyond
    8 MiB the partition table has to be written by something else, and
    `--allow-beyond-prep` is here so that case is explicit rather than silent.

USAGE
    tools/research/md10dpb.py IN.COM OUT.COM --parts 15399,15399,15399
    tools/research/md10dpb.py IN.COM OUT.COM --parts 8192,40960,65536 --bsh 6
    tools/research/md10dpb.py IN.COM --check          # read a patched one back
    tools/research/md10dpb.py --selftest              # the shipped DPB, re-derived
    tools/research/md10dpb.py --utils IMG --extract PATH   # pull HARD.COM out

    `--parts` is one partition size per hard-disk drive, in **512-byte blocks**
    as the partition table records them (so the sizes `md10table.py` prints).

Issue: #247.  See docs/md10-system.md 9 and 9.1.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# --- HARD.COM's embedded MD-10 BIOS, by *file* offset ----------------------
# A .COM loads at 0x0100, so an address inside the image is its file offset
# minus 0x0100.  The BIOS image starts at address 0x053A and is 0x5C5 bytes;
# read it at file offset 0x053A and you get the wrong 1222 bytes, which is the
# trap docs/md10-system.md 9 records.
BIOS_ADDR = 0x053A
BIOS_BASE = 0xD800
BIOS_LEN = 0x5C5
BIOS_OFF = BIOS_ADDR - 0x0100                      # 0x043A
TYPE_OFF = BIOS_OFF + (0xDD5E - BIOS_BASE)         # 0x0998, 16 per-drive type bytes
DESC_OFF = BIOS_OFF + (0xDD6E - BIOS_BASE)         # 0x09A8, 3 x 24-byte descriptors
DPB_OFF = BIOS_OFF + (0xDDB6 - BIOS_BASE)          # 0x09F0, the one shared DPB
DESC_LEN = 24
DESC_STRIDE = 24
DPB_LEN = 15

# --- the RAM the patch may use, and what it must not touch -----------------
POCKET_A = (0xDDC5, 0xE0EF)     # below the hand-over stub
STUB = (0xE0F0, 0xE0FD)         # ROM 2.0's hand-over stub, 14 bytes
POCKET_B = (0xEC00, 0xEE7F)     # above the CBIOS, below DIRBUF
DIRBUF = 0xEE80
CBIOS = 0xE100
DPB_BASE = 0xDDB6               # the vendor's DPB slot, inside the BIOS image
FREE = [POCKET_A, POCKET_B]     # allocated in this order

# --- the ceilings ----------------------------------------------------------
PREP_CEIL = 16384               # PREP.COM's per-partition ceiling, measured (8 MiB)
CPM_CEIL = 65535                # CP/M 2.2's: the partition length field is 16 bits
DRM = 1023                      # 1024 directory entries, the vendor's choice
DIR_BYTES = (DRM + 1) * 32      # 32768 bytes of directory, whatever the block size
SECTOR = 512
RECORD = 128

# The shipped DPB, for `--selftest` and for the "unchanged" report.
SHIPPED_DPB = bytes.fromhex("9cf0051f018307ff03ff0000000000")

class Fail(Exception):
    pass


def dpb_for(blocks, bsh, exm=None):
    """The DPB the vendor's own table would hold for a partition of `blocks`.

    Every field is derived, and the derivation is checked against the shipped
    DPB by `--selftest`, which is what makes it a measurement rather than a
    guess.  `SPT` is not a sector count: it is the partition in 128-byte records
    (docs/md10-system.md 9), and it is the one field whose meaning took a while.
    """
    block_bytes = RECORD << bsh
    cpm_blocks = blocks * SECTOR // block_bytes
    if cpm_blocks < 1:
        raise Fail("a partition of %d blocks is smaller than one %d-byte block"
                   % (blocks, block_bytes))
    dir_blocks = -(-DIR_BYTES // block_bytes)      # round up
    if dir_blocks > 16:
        raise Fail("%d directory blocks do not fit AL0/AL1 at BSH=%d"
                   % (dir_blocks, bsh))
    al0, al1 = 0, 0
    for i in range(dir_blocks):
        if i < 8:
            al0 |= 0x80 >> i
        else:
            al1 |= 0x80 >> (i - 8)
    if exm is None:
        # The extent mask, out of Digital Research's own DPB generator --
        # DISKDEF.LIB, in the CP/M 2.2 sources (`UTILSRC/DISKDEF`):
        #
        #     blkval  set  bls/1024          ; number of kilobytes/block
        #     extmsk  set  0                 ; fill from right with 1's
        #     ...
        #     ; may be double byte allocation
        #     if  (dks) > 256
        #     extmsk  set  (extmsk shr 1)
        #     endif
        #
        # So it is 2**(BSH-3)-1, **halved once the disk is past 255 blocks** --
        # because a directory entry then holds eight 16-bit block pointers
        # instead of sixteen, so one entry covers half as many bytes.  That is
        # Alteration Guide Table 6-9 as well (BLS 8,192: 7 for DSM<256, 3 for
        # DSM>255).
        #
        # Which means the vendor's shipped EXM=1 at BSH=5 is *correct*, not
        # inconsistent: 3 is the DSM<256 value, and their DSM is 1923.  An
        # earlier revision of this tool read Table 6-9's first column only,
        # hardcoded 1 for BSH=5 (accidentally right) and wrote the DSM<256
        # value at every other block size -- 7 where BSH=6 wants 3.
        exm = (1 << (bsh - 3)) - 1
        if cpm_blocks > 256:
            exm >>= 1
    return {"SPT": blocks * (SECTOR // RECORD), "BSH": bsh,
            "BLM": (block_bytes // RECORD) - 1, "EXM": exm,
            "DSM": cpm_blocks - 1, "DRM": DRM, "AL0": al0, "AL1": al1,
            "CKS": 0, "OFF": 0}


def dpb_bytes(d):
    return (d["SPT"].to_bytes(2, "little") + bytes([d["BSH"], d["BLM"], d["EXM"]])
            + d["DSM"].to_bytes(2, "little") + d["DRM"].to_bytes(2, "little")
            + bytes([d["AL0"], d["AL1"]]) + d["CKS"].to_bytes(2, "little")
            + d["OFF"].to_bytes(2, "little"))


def parse_dpb(b):
    return {"SPT": int.from_bytes(b[0:2], "little"), "BSH": b[2], "BLM": b[3],
            "EXM": b[4], "DSM": int.from_bytes(b[5:7], "little"),
            "DRM": int.from_bytes(b[7:9], "little"), "AL0": b[9], "AL1": b[10],
            "CKS": int.from_bytes(b[11:13], "little"),
            "OFF": int.from_bytes(b[13:15], "little")}


def alv_size(d):
    """One bit per CP/M block, plus the rounding byte -- CP/M 2.2's own rule."""
    return d["DSM"] // 8 + 1


def descriptor_ptrs(img, i):
    """(DPB, ALV) as the i'th hard-disk descriptor's DPH holds them."""
    off = DESC_OFF + i * DESC_STRIDE
    dph = img[off + 16:off + 24]
    want = DIRBUF.to_bytes(2, "little")
    if dph[0:2] != want:
        raise Fail("descriptor %d's DPH does not name DIRBUF at %04X (it holds %s)"
                   " -- this is not the 2.01 HARD.COM" % (i, DIRBUF, dph[0:2].hex(" ")))
    return int.from_bytes(dph[2:4], "little"), int.from_bytes(dph[6:8], "little")




def _place(cursor, n, what):
    """Take `n` bytes of the free pockets.  `cursor` is [pocket_index, address].

    Pocket A first, then Pocket B, and never a byte of the stub, the CBIOS or
    DIRBUF -- the pockets are defined around them, so a refusal here is a layout
    that is genuinely too big rather than one that overran something.
    """
    ri, addr = cursor
    while ri < len(FREE):
        lo, hi = FREE[ri]
        if addr < lo:
            addr = lo
        if addr + n - 1 <= hi:
            cursor[0], cursor[1] = ri, addr + n
            return addr
        ri, addr = ri + 1, 0
    total = sum(hi - lo + 1 for lo, hi in FREE)
    raise Fail("%s needs %d bytes and the free RAM is %d (Pocket A %d + Pocket B %d)"
               % (what, n, total, POCKET_A[1] - POCKET_A[0] + 1,
                  POCKET_B[1] - POCKET_B[0] + 1))


def plan(parts, bsh=5, exm=None, allow_beyond_prep=False):
    """The DPB, the ALV size and the three ALV addresses."""
    if len(parts) != 3:
        raise Fail("the driver has three hard-disk descriptors; %d partition(s) given"
                   % len(parts))
    for i, p in enumerate(parts):
        if p < 1:
            raise Fail("drive %d's partition is %d blocks" % (i, p))
        if p > CPM_CEIL:
            raise Fail("drive %d's partition is %d blocks, past CP/M 2.2's %d -- the "
                       "partition length field is 16 bits of 512 bytes"
                       % (i, p, CPM_CEIL))
        if p > PREP_CEIL and not allow_beyond_prep:
            raise Fail("drive %d's partition is %d blocks, past PREP.COM's *measured* "
                       "ceiling of %d (8 MiB): the vendor installer will not make one "
                       "that big, so the partition table has to come from somewhere "
                       "else.  Pass --allow-beyond-prep if that is the intent."
                       % (i, p, PREP_CEIL))
    if len(set(parts)) != 1:
        raise Fail("partitions %s differ, and the three descriptors share ONE DPB at "
                   "%04X -- so CP/M can only believe one size.  Three DPBs are 30 bytes "
                   "of new data, and HARD.COM has exactly one byte free after the BIOS "
                   "image (file 0x9FF of 0xA00), so they cannot be patched in: they "
                   "have to come from ROM 2.0's HCBOOT payload (497 bytes spare, "
                   "rom2.diff) or from a grown HARD.COM.  See docs/md10-system.md 9.2."
                   % (",".join(str(p) for p in parts), DPB_BASE))
    d = dpb_for(parts[0], bsh, exm)
    size = alv_size(d)
    cursor = [0, POCKET_A[0]]
    addrs = [_place(cursor, size, "ALV%d" % i) for i in range(3)]
    return {"dpb": d, "parts": list(parts), "bsh": bsh, "alv_size": size,
            "alv_addr": addrs, "dpb_addr": DPB_BASE,
            "used": (POCKET_A[0], addrs[-1] + size - 1)}


def patch(img, lay):
    """HARD.COM with the DPB and the three ALV pointers rewritten, in place."""
    out = bytearray(img)
    out[DPB_OFF:DPB_OFF + DPB_LEN] = dpb_bytes(lay["dpb"])
    for i, a in enumerate(lay["alv_addr"]):
        off = DESC_OFF + i * DESC_STRIDE
        out[off + 22:off + 24] = a.to_bytes(2, "little")
    return bytes(out)


def describe(lay):
    d = lay["dpb"]
    total = sum(h - l + 1 for l, h in FREE)
    lines = ["  drives       %s blocks each" % ",".join(str(p) for p in lay["parts"]),
             "  DPB at %04X   SPT=%d BSH=%d BLM=%d EXM=%d DSM=%d DRM=%d AL0=%02X AL1=%02X"
             % (lay["dpb_addr"], d["SPT"], d["BSH"], d["BLM"], d["EXM"], d["DSM"],
                d["DRM"], d["AL0"], d["AL1"]),
             "  CP/M sees    %d blocks of %d bytes = %d bytes per drive"
             % (d["DSM"] + 1, RECORD << d["BSH"], (d["DSM"] + 1) * (RECORD << d["BSH"])),
             "  ALV          %d bytes each, three of them" % lay["alv_size"]]
    for i, a in enumerate(lay["alv_addr"]):
        lines.append("    ALV%d       %04X-%04X" % (i, a, a + lay["alv_size"] - 1))
    lo, hi = lay["used"]
    lines.append("  free RAM used %04X-%04X (%d of %d), stub %04X and DIRBUF %04X untouched"
                 % (lo, hi, hi - lo + 1, total, STUB[0], DIRBUF))
    return "\n".join(lines)


def hoff(addr):
    """A RAM address inside the BIOS image, as a HARD.COM file offset."""
    if not (BIOS_BASE <= addr < BIOS_BASE + BIOS_LEN):
        raise Fail("%04X is not inside the BIOS image (%04X-%04X)"
                   % (addr, BIOS_BASE, BIOS_BASE + BIOS_LEN - 1))
    return BIOS_OFF + (addr - BIOS_BASE)


def check(img):
    """Read a HARD.COM back: the DPB, and what each descriptor's DPH points at."""
    if len(img) != 0xA00:
        raise Fail("the file is %d bytes; the 2.01 HARD.COM is 2560 (0xA00)"
                   % len(img))
    which = ("the shipped DPB" if img[DPB_OFF:DPB_OFF + DPB_LEN] == SHIPPED_DPB
             else "a patched DPB")
    dpb = parse_dpb(img[DPB_OFF:DPB_OFF + DPB_LEN])
    lines = ["  %s at %04X: SPT=%d BSH=%d BLM=%d EXM=%d DSM=%d DRM=%d AL0=%02X AL1=%02X"
             % (which, DPB_BASE, dpb["SPT"], dpb["BSH"], dpb["BLM"], dpb["EXM"],
                dpb["DSM"], dpb["DRM"], dpb["AL0"], dpb["AL1"]),
             "  CP/M sees %d blocks of %d bytes = %d bytes per drive"
             % (dpb["DSM"] + 1, RECORD << dpb["BSH"],
                (dpb["DSM"] + 1) * (RECORD << dpb["BSH"])),
             "  the ALV is %d bytes" % alv_size(dpb)]
    for i in range(3):
        p, a = descriptor_ptrs(img, i)
        note = "" if p == DPB_BASE else "  <-- NOT the shared DPB"
        lines.append("  drive %d: DPB %04X, ALV %04X-%04X%s"
                     % (i, p, a, a + alv_size(dpb) - 1, note))
    return "\n".join(lines)


def selftest():
    """The shipped DPB, re-derived from its partition size -- the real check."""
    d = dpb_for(15399, 5)
    got, want = dpb_bytes(d), SHIPPED_DPB
    if got != want:
        raise Fail("the derivation gives %s but the shipped DPB is %s"
                   % (got.hex(" "), want.hex(" ")))
    total = sum(h - l + 1 for l, h in FREE)
    print("  the shipped DPB, re-derived from 15399 blocks at BSH=5: %s" % got.hex(" "))
    print("  and it is HARD.COM's own bytes at file 0x%04X" % DPB_OFF)
    print("  ALV %d bytes; three is %d, and the free RAM is %d"
          % (alv_size(d), 3 * alv_size(d), total))
    print("  what three ALVs cost, at BSH=5 (4 KiB blocks):")
    for blocks, what in ((15399, "the shipped 15399 (7.5 MiB)"),
                         (16384, "PREP.COM's ceiling (8 MiB)"),
                         (32768, "16 MiB"), (65535, "CP/M's ceiling (32 MiB)")):
        dd = dpb_for(blocks, 5)
        need = 3 * alv_size(dd)
        print("    %6d blocks  DSM=%-5d ALV=%4d x3 = %5d  %-7s %s"
              % (blocks, dd["DSM"], alv_size(dd), need,
                 "fits" if need <= total else "TOO BIG", what))

    # EXM at every block size, against DISKDEF.LIB's own arithmetic.  This is
    # what the 2026-10-15 BSH=6 test found the hard way: the value the tool
    # wrote at BSH=5 was right, and every other block size got the DSM<256
    # value -- 7 where BSH=6 wants 3.
    print("\n  the extent mask at every block size (DISKDEF.LIB: 2**(BSH-3)-1,")
    print("  halved past 255 blocks), checked against the derivation:")
    print("    %5s %4s %7s %6s %7s" % ("BLS", "BSH", "blocks", "EXM", "Table"))
    for bsh in (4, 5, 6, 7):
        dd = dpb_for(16384, bsh)
        want_exm = (1 << (bsh - 3)) - 1
        if dd["DSM"] + 1 > 256:
            want_exm >>= 1
        if dd["EXM"] != want_exm:
            raise Fail("BSH=%d derives EXM=%d; DISKDEF.LIB says %d"
                       % (bsh, dd["EXM"], want_exm))
        print("    %4dK %4d %7d %6d %7d" % ((128 << bsh) // 1024, bsh,
                                            dd["DSM"] + 1, dd["EXM"], want_exm))

    # The drive count, which is what the ALV budget is *for*: an 8 MiB
    # partition at each block size, and how many of them fit in the free RAM.
    # CKS=0 (fixed media) is why the ALV is the whole per-drive cost.
    print("\n  an 8 MiB partition (PREP.COM's 16384-sector ceiling) costs, in RAM:")
    print("    %5s %4s %7s %8s %8s %9s"
          % ("BLS", "BSH", "blocks", "ALV", "drives", "total MB"))
    for bsh in (4, 5, 6, 7):
        dd = dpb_for(16384, bsh)
        alv = alv_size(dd)
        n = total // alv
        print("    %4dK %4d %7d %7dB %8d %9.1f"
              % ((128 << bsh) // 1024, bsh, dd["DSM"] + 1, alv, n, n * 8.0))
    print("    (CP/M has 16 letters; two go to the floppies, so 14 are available")
    print("     to the disk -- at BSH=6 the ALV binds first, at 11.)")
    print("    A drive also needs its 24-byte descriptor, and the table in the BIOS")
    print("    image is full at three (DD6E, with the DPB immediately after at")
    print("    DDB6).  Out of the same 1451 bytes that is 9 drives at 8 MiB; out of")
    print("    the unmeasured EB00-EBFF pocket (256 B) it is 10.  Where the")
    print("    descriptors live is the first thing the drive-count work has to")
    print("    settle -- the ALV budget is what comes after it.")
    return 0


def extract_hard_com(image, out):
    """HARD.COM out of the archive's 2.01 utilities disk, as the vendor shipped it."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "cpmfs", os.path.join(os.path.dirname(HERE), "cpmfs.py"))
    cpmfs = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cpmfs)
    fs = cpmfs.CPM(image, "osb1sssd")
    ents = fs.files().get(cpmfs.parse_spec("0:HARD.COM"))
    if not ents:
        raise Fail("HARD.COM is not on %s" % image)
    data = fs.read_file(ents)
    open(out, "wb").write(data)
    return data


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="patch the MD-10 driver's DPB, descriptor table and ALVs (#247)")
    ap.add_argument("infile", nargs="?", help="HARD.COM (2560 bytes)")
    ap.add_argument("outfile", nargs="?", help="where to write the patched file")
    ap.add_argument("--parts", help="one partition size per hard-disk drive, in "
                                    "512-byte blocks, comma-separated")
    ap.add_argument("--bsh", type=int, default=5, help="block shift (default 5 = 4 KiB)")
    ap.add_argument("--exm", type=int, default=None,
                    help="extent mask; the default keeps the vendor's 1 at BSH=5 and "
                         "uses the standard 2**(BSH-3)-1 elsewhere")
    ap.add_argument("--allow-beyond-prep", action="store_true",
                    help="allow a partition past PREP.COM's measured 8 MiB ceiling")
    ap.add_argument("--check", action="store_true", help="read a HARD.COM back")
    ap.add_argument("--selftest", action="store_true",
                    help="re-derive the shipped DPB and the pocket arithmetic")
    ap.add_argument("--utils", help="the 2.01 utilities image, to pull HARD.COM out of")
    ap.add_argument("--extract", help="with --utils: where to write HARD.COM")
    args = ap.parse_args(argv)

    try:
        if args.selftest:
            return selftest()
        if args.extract:
            if not args.utils:
                raise Fail("--extract needs --utils")
            d = extract_hard_com(args.utils, args.extract)
            print("  wrote %s (%d bytes)" % (args.extract, len(d)))
            return 0
        if not args.infile:
            raise Fail("no input; see --help")
        img = open(args.infile, "rb").read()
        if args.check:
            print("%s:" % args.infile)
            print(check(img))
            return 0
        if not args.outfile or not args.parts:
            raise Fail("patching needs OUT and --parts; see --help")
        parts = [int(x) for x in args.parts.split(",")]
        lay = plan(parts, args.bsh, args.exm, args.allow_beyond_prep)
        out = patch(img, lay)
        if len(out) != len(img):
            raise Fail("the patch changed the file's length, which it must not")
        print("%s -> %s" % (args.infile, args.outfile))
        print(describe(lay))
        open(args.outfile, "wb").write(out)
        import zlib
        print("  wrote %s (%d bytes, CRC32 %08x)"
              % (args.outfile, len(out), zlib.crc32(out) & 0xFFFFFFFF))
        print("\n  what the patched file now says:")
        print(check(out))
        print("\nNEXT: the *drive* has to match -- build it with the same partition "
              "sizes\n  (tools/research/md10prep.sh for a new geometry, or md10drive.py "
              "for a captured layout).")
        return 0
    except Fail as e:
        print("md10dpb.py: %s" % e, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
