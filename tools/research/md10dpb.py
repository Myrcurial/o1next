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


# --- the N-drive build (#247 step 6) ---------------------------------------
# The shipped driver presents three hard-disk drives with three 24-byte
# descriptors at DD6E: an 8-byte partition record (select byte, 16-bit start,
# one byte, 16-bit length, two spare) followed by a 16-byte DPH.  All three
# DPHs name the same DPB at DDB6 and the same DIRBUF, and only the ALV
# differs.  The descriptors and the DPB are the *whole* of DD6E-DDC4 -- the
# last 87 bytes of the BIOS image -- so that region is the only home an
# N-drive table has, and the ALVs keep the 1451 bytes of Pocket A and Pocket B
# (the BDOS zeroes an ALV at cold boot, which is why the vendor's descriptors
# can point at RAM nothing in the image initialises).
#
# What a drive costs, and what is shared:
#
#   per drive   the partition's **start LBA, 24-bit**.  Sixteen bits is not
#               enough: eleven 7.5 MiB partitions end at LBA 154010, and the
#               card's CDB takes a 24-bit LBA -- the shipped driver's
#               `adc a,0` carry is exactly that high byte.  Plus its **ALV
#               pointer**, the one field that must genuinely differ.
#   shared      one 16-byte DPH, one DPB, and the select byte and the
#               partition length -- which are per *drive*, not per partition,
#               so they are constants here.  **Equal partitions are therefore
#               a condition of the build, not a convenience**: one DPB cannot
#               describe two sizes and N DPBs do not fit (9.2).
#
# So an entry is five bytes, and the region has to hold 5N + 16 + 15 <= 87:
#
#   DD6E              5N   the per-drive table: start(3) then ALV(2)
#   DD6E + 5N         16   the shared DPH
#   DD6E + 5N + 16    15   the DPB
#
# At N = 11 that is 86 of the 87 bytes.  A layout that does not fit is
# refused, with the arithmetic -- there is no second home to spill into.
#
# KNOWN DEFECT (2026-10-15, #247) -- READ THIS BEFORE USING IT
#     The driver this builds **boots**: the ROM hands over to it, it reaches
#     `A0>` with no floppy, and its type table, per-drive table, shared DPH,
#     DPB and ALVs are all correct in RAM.  It cannot, however, read drive
#     `A:`'s directory: `DIR A:` answers `No file` and a `SAVE` answers
#     `No space`, while `B:` works.  The vendor's driver does both on the same
#     drive, and every observable cell -- the BDOS's own cells and the driver's
#     read cache -- is **byte-identical** between the two, so the difference is
#     in the card traffic and has not been found.  A per-drive-DPH variant
#     fails identically, so it is not the shared DPH.  Do not treat the output
#     as a working driver; the issue's handover comment has the evidence.
#
# Two routines change, and both stay inside the space they already occupy:
#
#   SELDSK's hard-disk tail (D8F6, 21 of the 23 bytes to D90C) stops doing
#     `descriptor = 0xDD6E + type*24` and copies the drive's ALV pointer into
#     the shared DPH instead.  The DPH's address is a *constant* now, so
#     `ld (0dd55h),hl` leaves the routine and moves into the image: DD55 is
#     pre-set to it, and the loader copies that byte like any other.  (The
#     routine is entered by `jp p,0d8f6h` from the prologue, which does not
#     change, and nothing else in the driver jumps into the tail.)
#
#   the LBA routine (D90D, 42 of the 45 bytes to D939) stops reading the
#     descriptor's 8-byte prefix and reads the drive's 24-bit start out of the
#     table instead.  `LBA = sector + start` is unchanged, carry and all, and
#     the two call sites (DA0E, DA4E) are not touched.
#
# The type table at DD5E becomes `00 01 .. 0(N-1)` then the floppy types, so
# drives 0..N-1 are hard-disk descriptors and the floppies move up -- which is
# the documented consequence, not a surprise: on eleven partitions the two
# floppies are `L:` and `M:` (docs/md10-system.md 9.3).
GROW_TABLE = 0xDD6E                         # where the descriptors were
GROW_ENTRY = 5                              # start(3) + ALV(2)
GROW_LAST = BIOS_BASE + BIOS_LEN - 1        # 0xDDC4: the last byte of the image
GROW_DPH_LEN = 16
GROW_DPB_LEN = 15
SELDSK_TAIL = 0xD8F6                        # the hard-disk branch
SELDSK_SLOT = 0xD90D - SELDSK_TAIL          # 23 bytes before the LBA routine
LBA_ROUTINE = 0xD90D                        # called from DA0E and DA4E
LBA_SLOT = 0xD93A - LBA_ROUTINE             # 45 bytes before HOME
DPH_CELL = 0xDD55                           # the driver's saved DPH pointer
TYPE_BASE = 0xDD5E
TYPE_LEN = 16
LABEL_PART_OFF = 48                         # LBA 0 +48, 28-byte records
LABEL_PART_LEN = 28
LABEL_END = 0xFF                            # the terminator PREP.COM writes


def read_label_partitions(image):
    """A drive's partition table as [(start, blocks, name)] -- LBA 0, +48.

    The walk and the record layout are `tools/research/md10table.py`'s; it is
    six lines and duplicating them keeps this tool dependency-free.
    """
    if image[:2] != b"MD":
        raise Fail("this is not an MD-10 drive: LBA 0 starts %s, not 'MD'"
                   % image[:2].hex(" "))
    out = []
    for i in range(64):
        o = LABEL_PART_OFF + i * LABEL_PART_LEN
        rec = image[o:o + LABEL_PART_LEN]
        if len(rec) < LABEL_PART_LEN or rec[0] == LABEL_END:
            break
        start = int.from_bytes(rec[1:4], "little")
        blocks = int.from_bytes(rec[4:6], "little")
        name = rec[16:26].split(b"\x00")[0].decode("latin1")
        out.append((start, blocks, name))
    return out


def seldsk_tail(table, dph):
    """The new hard-disk branch of SELDSK: return the shared DPH, for `type`.

    Entered with A = the per-drive type byte, which for a hard disk *is* the
    drive index.  Five bytes an entry, so the index is `5 x type` -- which is
    `type x 4 + type`, four one-byte instructions rather than a multiply.  The
    table is addressed three bytes in, so the ALV field is at entry+0 and the
    three `inc hl` a `+0` base would need are not there -- that is what pays
    for `ld hl,dph` and keeps this inside the 23-byte slot.

    HL on return **is** the DPH; that is the routine's whole contract, and
    leaving it holding the table address is not a subtle failure -- the BDOS
    dereferences it, reads a garbage DPB, and spins in its own division
    (docs/md10-system.md 9.4).
    """
    b = bytearray()
    b += bytes([0x6F])                      # ld  l,a
    b += bytes([0x87, 0x87])                # add a,a / add a,a   4 x type
    b += bytes([0x85])                      # add a,l             5 x type
    b += bytes([0x6F])                      # ld  l,a
    b += bytes([0x26, 0x00])                # ld  h,0
    b += bytes([0x11]) + (table + 3).to_bytes(2, "little")   # ld de,TABLE+3
    b += bytes([0x19])                      # add hl,de           &entry.alv
    b += bytes([0x5E])                      # ld  e,(hl)
    b += bytes([0x23])                      # inc hl
    b += bytes([0x56])                      # ld  d,(hl)          DE = the ALV
    b += bytes([0xED, 0x53]) + (dph + 14).to_bytes(2, "little")
    b += bytes([0x21]) + dph.to_bytes(2, "little")   # ld hl,dph  <- the DPH
    b += bytes([0xC9])                      # ret
    return bytes(b)


def lba_routine(table, blocks):
    """The new LBA routine: CDB LBA = the drive's start + this sector.

    Entered with the drive number in 0x0D96F, and it returns carry **set** on
    success -- which is what DA11's `jr nc` reads.  The guard is the shipped
    one: a sector past the partition length is refused rather than wrapped.
    """
    b = bytearray()
    b += bytes([0x3A, 0x6F, 0xD9])          # ld  a,(0d96fh)      the drive
    b += bytes([0x6F])                      # ld  l,a
    b += bytes([0x87, 0x87])                # add a,a / add a,a
    b += bytes([0x85])                      # add a,l
    b += bytes([0x6F])                      # ld  l,a
    b += bytes([0x26, 0x00])                # ld  h,0
    b += bytes([0x11]) + table.to_bytes(2, "little")   # ld de,TABLE
    b += bytes([0x19])                      # add hl,de
    b += bytes([0x5E])                      # ld  e,(hl)          start, low
    b += bytes([0x23])                      # inc hl
    b += bytes([0x56])                      # ld  d,(hl)          start, high
    b += bytes([0x23])                      # inc hl
    b += bytes([0x7E])                      # ld  a,(hl)          start, top
    b += bytes([0x2A, 0x70, 0xD9])          # ld  hl,(0d970h)     the sector
    b += bytes([0x01]) + blocks.to_bytes(2, "little")  # ld bc,length
    b += bytes([0xE5])                      # push hl
    b += bytes([0xED, 0x42])                # sbc hl,bc
    b += bytes([0xE1])                      # pop hl
    b += bytes([0xD0])                      # ret nc              past the end
    b += bytes([0x19])                      # add hl,de
    b += bytes([0x30, 0x01])                # jr nc,$+3
    b += bytes([0x3C])                      # inc a               the carry
    b += bytes([0x22, 0xFC, 0xD9])          # ld (0d9fch),hl      CDB LBA
    b += bytes([0x32, 0xFB, 0xD9])          # ld (0d9fbh),a       CDB byte 1
    b += bytes([0x37])                      # scf
    b += bytes([0xC9])                      # ret
    return bytes(b)


def grow_plan(parts, bsh=6):
    """The N-drive layout: the table, the shared DPH and the DPB, and where.

    `parts` is [(start, blocks)] per CP/M drive in drive order -- a drive's own
    partition table minus its first record, which is the O/S partition
    (`CP/M-CCP`) and not a CP/M drive.
    """
    n = len(parts)
    if n < 1:
        raise Fail("no CP/M partitions: the first record of an MD-10 drive's "
                   "label is the O/S partition, not a drive")
    if n > TYPE_LEN - 2:
        raise Fail("%d drives leaves no room for the two floppies in the type "
                   "table at %04X (%d bytes)" % (n, TYPE_BASE, TYPE_LEN))
    if len(set(b for _, b in parts)) != 1:
        raise Fail("the partitions differ (%s) and this build shares ONE DPB, "
                   "so equal partitions are a condition of it -- PREP.COM's "
                   "option 4, not option 5 (9.2)"
                   % ",".join(str(b) for _, b in parts))
    for i, (start, blk) in enumerate(parts):
        if start < 20:
            raise Fail("drive %d starts at LBA %d, inside the header"
                       % (i, start))
        if start > 0xFFFFFF:
            raise Fail("drive %d starts at LBA %d, past the card's 24-bit CDB"
                       % (i, start))
    d = dpb_for(parts[0][1], bsh)
    size = alv_size(d)
    table = GROW_TABLE
    dph = table + GROW_ENTRY * n
    dpb = dph + GROW_DPH_LEN
    end = dpb + GROW_DPB_LEN - 1
    if end > GROW_LAST:
        raise Fail("the N-drive tables need %d bytes (%d x %d for the table, "
                   "%d for the DPH, %d for the DPB) and %04X-%04X is %d -- "
                   "N=%d does not fit"
                   % (end - table + 1, n, GROW_ENTRY, GROW_DPH_LEN, GROW_DPB_LEN,
                      table, GROW_LAST, GROW_LAST - table + 1, n))
    cursor = [0, POCKET_A[0]]
    alv = [_place(cursor, size, "ALV%d" % i) for i in range(n)]
    if alv[-1] + size - 1 > POCKET_B[1]:
        raise Fail("the ALVs end at %04X and the free RAM ends at %04X"
                   % (alv[-1] + size - 1, POCKET_B[1]))
    return {"parts": list(parts), "n": n, "bsh": bsh, "dpb": d, "alv_size": size,
            "alv_addr": alv, "table": table, "dph": dph, "dpb_addr": dpb,
            "blocks": parts[0][1]}


def _put(out, off, data):
    out[off:off + len(data)] = data
    return len(data)


def grow_patch(img, lay):
    """HARD.COM with the N-drive driver in it: code, tables and all."""
    out = bytearray(img)
    n, dph, dpb = lay["n"], lay["dph"], lay["dpb_addr"]

    # the type table: drives 0..N-1 are hard-disk descriptors, then floppies
    types = bytes(range(n)) + bytes(0x80 + i for i in range(TYPE_LEN - n))
    o = hoff(TYPE_BASE)
    out[o:o + TYPE_LEN] = types

    # the per-drive table, then the shared DPH, then the DPB
    o = hoff(GROW_TABLE)
    for i, (start, _) in enumerate(lay["parts"]):
        o += _put(out, o, start.to_bytes(3, "little"))
        o += _put(out, o, lay["alv_addr"][i].to_bytes(2, "little"))
    if o != hoff(dph):
        raise Fail("internal: the table ended at %04X, not %04X"
                   % (BIOS_BASE + o - BIOS_OFF, dph))
    out[o:o + GROW_DPH_LEN] = (bytes(8) + DIRBUF.to_bytes(2, "little")
                               + dpb.to_bytes(2, "little") + bytes(2)
                               + lay["alv_addr"][0].to_bytes(2, "little"))
    o += GROW_DPH_LEN
    if o != hoff(dpb):
        raise Fail("internal: the DPH ended at %04X, not %04X"
                   % (BIOS_BASE + o - BIOS_OFF, dpb))
    out[o:o + GROW_DPB_LEN] = dpb_bytes(lay["dpb"])

    # the saved DPH is a constant now, so it lives in the image
    o = hoff(DPH_CELL)
    out[o:o + 2] = dph.to_bytes(2, "little")

    # the two routines, each padded with NOPs to the end of its own slot
    tail = seldsk_tail(lay["table"], dph)
    if len(tail) > SELDSK_SLOT:
        raise Fail("the SELDSK tail is %d bytes and its slot is %d"
                   % (len(tail), SELDSK_SLOT))
    lba = lba_routine(lay["table"], lay["blocks"])
    if len(lba) > LBA_SLOT:
        raise Fail("the LBA routine is %d bytes and its slot is %d"
                   % (len(lba), LBA_SLOT))
    o = hoff(SELDSK_TAIL)
    out[o:o + SELDSK_SLOT] = tail + bytes(SELDSK_SLOT - len(tail))
    o = hoff(LBA_ROUTINE)
    out[o:o + LBA_SLOT] = lba + bytes(LBA_SLOT - len(lba))
    return bytes(out)


def grow_describe(lay):
    d, n = lay["dpb"], lay["n"]
    lines = ["  drives       %d, equal: %d blocks (%.1f MiB) each"
             % (n, lay["blocks"], lay["blocks"] * SECTOR / 1048576.0),
             "  table at %04X  %d x %d bytes, ends %04X"
             % (lay["table"], n, GROW_ENTRY, lay["table"] + GROW_ENTRY * n - 1),
             "  shared DPH   %04X-%04X (the saved pointer at %04X)"
             % (lay["dph"], lay["dph"] + GROW_DPH_LEN - 1, DPH_CELL),
             "  DPB at %04X  SPT=%d BSH=%d BLM=%d EXM=%d DSM=%d DRM=%d AL0=%02X AL1=%02X"
             % (lay["dpb_addr"], d["SPT"], d["BSH"], d["BLM"], d["EXM"], d["DSM"],
                d["DRM"], d["AL0"], d["AL1"]),
             "  CP/M sees    %d blocks of %d bytes = %d bytes per drive"
             % (d["DSM"] + 1, RECORD << d["BSH"],
                (d["DSM"] + 1) * (RECORD << d["BSH"])),
             "  ALV          %d bytes each; %d of them is %d of the %d free"
             % (lay["alv_size"], n, n * lay["alv_size"],
                sum(h - l + 1 for l, h in FREE))]
    for i, a in enumerate(lay["alv_addr"]):
        if i < 3 or i == n - 1:
            lines.append("    ALV%-2d       %04X-%04X"
                         % (i, a, a + lay["alv_size"] - 1))
        elif i == 3:
            lines.append("    ...")
    lines.append("  type table   %s"
                 % " ".join("%02X" % t for t in
                            list(range(n)) + [0x80 + i for i in range(TYPE_LEN - n)]))
    lines.append("  the floppies move up: drive %d is floppy A (%02X), %d is B"
                 % (n, 0x80, n + 1))
    return "\n".join(lines)


def grow_check(img):
    """Read a grown driver back, or None if this is not one.

    The marker is DD55: the shipped driver rewrites it on every SELDSK, and the
    grown one never does -- it is a constant pointing into the table region.
    """
    if len(img) != 0xA00:
        raise Fail("the file is %d bytes; the 2.01 HARD.COM is 2560 (0xA00)"
                   % len(img))
    o = hoff(DPH_CELL)
    dph = int.from_bytes(img[o:o + 2], "little")
    if not (GROW_TABLE < dph <= GROW_LAST):
        return None
    types = img[hoff(TYPE_BASE):hoff(TYPE_BASE) + TYPE_LEN]
    n = 0
    while n < TYPE_LEN and types[n] == n:
        n += 1
    dpb_addr = dph + GROW_DPH_LEN
    dpb = parse_dpb(img[hoff(dpb_addr):hoff(dpb_addr) + DPB_LEN])
    parts = []
    for i in range(n):
        o = hoff(GROW_TABLE) + i * GROW_ENTRY
        start = int.from_bytes(img[o:o + 3], "little")
        alv = int.from_bytes(img[o + 3:o + 5], "little")
        parts.append((start, alv))
    lines = ["  a GROWN driver: %d hard-disk drives, then the floppies" % n,
             "  type table   %s"
             % " ".join("%02X" % t for t in types),
             "  table at %04X  %d x %d bytes" % (GROW_TABLE, n, GROW_ENTRY),
             "  shared DPH   %04X (the saved pointer at %04X)"
             % (dph, DPH_CELL),
             "  DPB at %04X  SPT=%d BSH=%d BLM=%d EXM=%d DSM=%d DRM=%d AL0=%02X AL1=%02X"
             % (dpb_addr, dpb["SPT"], dpb["BSH"], dpb["BLM"], dpb["EXM"],
                dpb["DSM"], dpb["DRM"], dpb["AL0"], dpb["AL1"]),
             "  CP/M sees    %d blocks of %d bytes = %d bytes per drive"
             % (dpb["DSM"] + 1, RECORD << dpb["BSH"],
                (dpb["DSM"] + 1) * (RECORD << dpb["BSH"])),
             "  ALV is %d bytes; %d of them is %d"
             % (alv_size(dpb), n, n * alv_size(dpb))]
    for i, (start, alv) in enumerate(parts):
        if i < 3 or i == n - 1:
            lines.append("    drive %-2d    start %-7d ALV %04X-%04X"
                         % (i, start, alv, alv + alv_size(dpb) - 1))
        elif i == 3:
            lines.append("    ...")
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
    print("    The *descriptor* is the other half of the cost, and DD6E-DDC4 is")
    print("    descriptors and DPB and nothing else -- so an N-drive table has")
    print("    to fit in those 87 bytes, with one shared DPH and one shared DPB:")
    print("        5N + 16 + 15 <= 87   ->   N <= 11")
    print("    and an entry is five bytes because the start is 24-bit: eleven")
    print("    7.5 MiB partitions end at LBA 154010, past a 16-bit field.")

    # The N-drive build (step 6), on the settled layout.  This is the
    # arithmetic check and a round trip through grow_patch/grow_check; the
    # routines' *behaviour* is rom2-check.sh's job, in the machine.
    print("\n  the N-drive build, at the settled 11 x 15399 blocks:")
    parts = [(20 + i * 15399, 15399) for i in range(11)]
    lay = grow_plan(parts, 6)
    for line in grow_describe(lay).splitlines():
        print(line)
    img = grow_patch(bytes(0xA00), lay)
    back = grow_check(img)
    if back is None:
        raise Fail("grow_patch wrote a driver grow_check does not recognise")
    for line in back.splitlines()[1:4]:
        print(line)
    if int.from_bytes(img[hoff(DPH_CELL):hoff(DPH_CELL) + 2], "little") != lay["dph"]:
        raise Fail("the saved-DPH cell does not hold the shared DPH")
    tail, lba = seldsk_tail(lay["table"], lay["dph"]), lba_routine(
        lay["table"], lay["blocks"])
    print("  the code     SELDSK tail %d of %d bytes, LBA routine %d of %d"
          % (len(tail), SELDSK_SLOT, len(lba), LBA_SLOT))
    for what, fn in (("unequal partitions", lambda: grow_plan(
                        [(20, 15399), (15419, 11544)], 6)),
                     ("twelve drives", lambda: grow_plan(
                        [(20 + i * 15399, 15399) for i in range(12)], 6))):
        try:
            fn()
        except Fail:
            print("  refuses      %s" % what)
        else:
            raise Fail("the tool accepted %s, which does not fit" % what)
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
    ap.add_argument("--bsh", type=int, default=None,
                    help="block shift (default: 5 = 4 KiB for --parts, 6 = 8 KiB "
                         "for --grow, which is what makes eleven ALVs fit)")
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
    ap.add_argument("--grow", action="store_true",
                    help="build the N-drive driver (step 6): the drive count and "
                         "the partition starts come from --drive")
    ap.add_argument("--drive", help="with --grow: the configured drive as a raw "
                                    "image, whose label says how many CP/M "
                                    "drives there are and where each starts")
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
            grown = grow_check(img)
            print(grown if grown else check(img))
            return 0
        if args.grow:
            if not (args.outfile and args.drive):
                raise Fail("--grow needs OUT and --drive; see --help")
            drive = open(args.drive, "rb").read()
            recs = read_label_partitions(drive)
            if len(recs) < 2:
                raise Fail("%s carries %d partition record(s), and the first is "
                           "the O/S partition -- so there is no CP/M drive to "
                           "present" % (args.drive, len(recs)))
            lay = grow_plan([(s, b) for s, b, _ in recs[1:]],
                            6 if args.bsh is None else args.bsh)
            out = grow_patch(img, lay)
            if len(out) != len(img):
                raise Fail("the patch changed the file's length, which it must not")
            print("%s -> %s  (from %s: %d CP/M partitions)"
                  % (args.infile, args.outfile, args.drive, len(recs) - 1))
            print(grow_describe(lay))
            open(args.outfile, "wb").write(out)
            import zlib
            print("  wrote %s (%d bytes, CRC32 %08x)"
                  % (args.outfile, len(out), zlib.crc32(out) & 0xFFFFFFFF))
            print("\n  what the patched file now says:")
            print(grow_check(out))
            print("\n  WARNING: this driver boots and its tables are correct, "
                  "but it cannot read\n  drive A:'s directory (`DIR A:` -> "
                  "`No file`, `SAVE` -> `No space`) while B:\n  works.  See "
                  "#247's handover comment before using it for anything.")
            print("\nNEXT: rom2image.py --hard, then rom2-check.sh with "
                  "O1_HARD=<the drive>\n  (tools/emulator-setup/mame-osborne1nx/)")
            return 0
        if not args.outfile or not args.parts:
            raise Fail("patching needs OUT and --parts; see --help")
        parts = [int(x) for x in args.parts.split(",")]
        lay = plan(parts, 5 if args.bsh is None else args.bsh, args.exm,
                   args.allow_beyond_prep)
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
