#!/usr/bin/env python3
"""rom2image.py -- assemble the ROM 2.0 image from the repo's own files.

WHY THIS EXISTS
    #83's deliverable 2 is "sources assembled into a ROM image".  The ROM 2.0
    design (`docs/o1-rom-2.0.md`) settles that image's *contents* at 7681 bytes
    (section 2.3), every one of them measured off a shipped artefact.  This tool
    builds the image from those artefacts and re-checks every number the design
    quotes, so the image is reproducible instead of described.

WHAT GOES IN (docs/o1-rom-2.0.md section 2.3)
    4096  monitor ROM          `research/roms/os1-144.rom` (stock 1.44 for now)
    2048  CBIOS                the system image, offset 0x1600, off OS1SYSD.IMD
    1477  MD-10 BIOS image     `HARD.COM`, file offset 0x053A
      60  install/patch/jump   `HARD.COM`, file offsets 0x00E5-0x0120
    ----
    7681  and it fits the 8 KB contiguous ROM window with 511 bytes to spare

    The **CCP and BDOS are not here**, by design: the ACB-4000 supplies them (11
    blocks from LBA 5 into 0xC200).  Nor are the loader's other 1022 bytes --
    HARD.COM is 2560 (a 1082-byte loader and a 1478-byte embedded BIOS), and the
    part left out is the banner, the presence probe and the TEST UNIT READY, which
    are diagnostics for a human installing a card.

THE LAYOUT
    0000-0FFF  monitor (4096)          always mapped, never banked
    1000-17FF  CBIOS        -> 0xE100  the running BIOS the MD-10 BIOS patches from
    1800-1DC4  MD-10 BIOS   -> 0xD800  copied by the shim
    1DC5-1E00  the shim (60)           called from the monitor
    1E01-1FFF  spare (511)             the boot screen, and the new features

    The payload occupies the window `1000-1FFF`; where it is *presented* is the
    interposer's softROM decision and is open (`docs/o1-rom-2.0.md` section 4.1a).

THE SHIM IS THE VENDOR'S OWN BYTES, NOT A REWRITE
    The 60 bytes at `HARD.COM` 0x01E5-0x0220 are lifted verbatim.  Exactly two of
    them are position-dependent -- the operand of `LD HL,nn` (the BIOS image's
    source address) and the operand of `LD BC,(nn)` (the length, read out of the
    image itself at +0x0D) -- and those two are relocated here.  Everything else
    in the shim names a fixed address (`0xD800`, the five `LDIR` destinations,
    `JP 0D800h`), so it needs no patching.

WHAT IT CHECKS, AND WHY IT EXITS NON-ZERO
    Every anchor the design rests on.  A build that silently produces a
    different image is worse than one that fails, so a moved anchor is a failure:

      * the monitor's CRC32 is `c0596b14` (`docs/o1-rom-source.md`);
      * the system image's four anchors on `OS1SYSD.IMD` -- the CCP's `c3 5c ce`,
        the BDOS entry's `c3 11 d3`, the CBIOS jump table at offset 0x1600, and
        its 13 `CD 12 E3` (`docs/o1-rom-2.0.md` section 2.1);
      * `HARD.COM` is 2560 bytes and its embedded BIOS starts at 0x053A with a
        length operand of 0x5C5 at 0x0547 (`docs/md10-system.md` section 4);
      * the shim's five `LDIR` sizes are 18 / 21 / 3 / 3 / 45 -- the 90 bytes of
        CBIOS vectors 2-31 the MD-10 BIOS borrows (`docs/o1-rom-2.0.md` 4.6).

Usage:
    tools/research/rom2image.py                  # build to /tmp/rom2.rom
    tools/research/rom2image.py -o out.rom
    tools/research/rom2image.py --monitor rom2.asm.bin    # once rom2.asm exists
    tools/research/rom2image.py --payload-only            # the 3585-byte payload
"""
import argparse
import importlib.util
import os
import sys
import zlib

# --- the image ------------------------------------------------------------

MONITOR_SIZE = 4096          # 0x0000-0x0FFF, the 2732 at UD11; never banked
WINDOW = 0x1000              # 0x1000-0x1FFF, the softROM's window
WINDOW_SIZE = 4096

CBIOS_OFF = 0x0000           # within the payload
CBIOS_SIZE = 2048
MD10_OFF = 0x0800
MD10_SIZE = 1477             # 0x5C5, read out of HARD.COM itself
SHIM_OFF = 0x0DC5
SHIM_SIZE = 60
PAYLOAD_SIZE = 3585          # CBIOS + MD-10 + shim; 511 spare behind it

# --- where the pieces land in RAM (what the shim and the CBIOS expect) -----

CBIOS_RAM = 0xE100
MD10_RAM = 0xD800

# --- HARD.COM -------------------------------------------------------------
#
# HARD.COM is a CP/M .COM, so CP/M loads it at 0x0100: **file offset = address
# - 0x0100**.  The design quotes addresses (`docs/md10-system.md` section 4), so
# they are addresses here too, and `hoff()` is the only place the difference
# lives.  Getting this wrong reads the length operand out of the middle of the
# BIOS image and produces 0x6F3A instead of 0x05C5.

HARD_BASE = 0x0100
HARD_SIZE = 2560             # 0x0A00: 1082-byte loader + 1478-byte embedded BIOS
HARD_BIOS_ADDR = 0x053A      # the embedded BIOS
HARD_LEN_ADDR = 0x0547       # the operand the shim reads as the copy length
HARD_LEN = 0x05C5            # = MD10_SIZE
HARD_SHIM_ADDR = 0x01E5      # the copy/patch/jump block
SHIM_LEN_OPERAND = 1         # shim+1,+2 = `LD HL,nn`, the BIOS source address
SHIM_LDBC_OPERAND = 8        # shim+8,+9 = `LD BC,(nn)`, the same address + 0x0D
SHIM_LEN_DELTA = 0x0D        # 0x0547 - 0x053A


def hoff(addr):
    """A HARD.COM address -> its offset in the file."""
    return addr - HARD_BASE


# --- the anchors ----------------------------------------------------------

ROM_CRC32 = 0xC0596B14
CCP_HEAD = bytes([0xC3, 0x5C, 0xCE])          # JP 0CE5Ch; 0xCE-3 = 0xCB = the CCP page
BDOS_ENTRY_OFF = 0x0806
BDOS_ENTRY = bytes([0xC3, 0x11, 0xD3])        # JP 0D311h
CBIOS_OFF_IN_IMAGE = 0x1600
CBIOS_VEC19 = bytes([0xCD, 0x12, 0xE3])       # ROMCDE, 13 times
CBIOS_VEC19_COUNT = 13
LDIR_SIZES = (18, 21, 3, 3, 45)

# --------------------------------------------------------------------------
# reading the inputs
# --------------------------------------------------------------------------

def _sibling(name):
    """Import a repo script by path: `tools/research/` first, then `tools/`.

    They are scripts, not packages, so this is the honest way to reach them --
    and it keeps the tool stdlib-only rather than duplicating an IMD reader or a
    CP/M filesystem reader that the repo already has.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (here, os.path.dirname(here)):
        path = os.path.join(d, name)
        if os.path.exists(path):
            break
    else:
        raise SystemExit("rom2image.py: cannot find %s beside this tool" % name)
    spec = importlib.util.spec_from_file_location(name[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def read_sys_image(imd, work):
    """The 7680-byte CCP+BDOS+CBIOS image off a shipped system disk.

    `imdinfo.py --raw` de-skews into logical sector order, which is the whole
    reason this is not a slice of the file (see its header, and #81).
    """
    imdinfo = _sibling("imdinfo.py")
    raw = os.path.join(work, "sys.raw")
    imdinfo.report(imd, raw_out=raw)
    return open(raw, "rb").read()[:0x1E00]


def read_hard_com(disk):
    """HARD.COM off the 2.01 utilities disk, as the vendor shipped it."""
    cpmfs = _sibling("cpmfs.py")
    fs = cpmfs.CPM(disk, "osb1sssd")
    ents = fs.files().get(cpmfs.parse_spec("0:HARD.COM"))
    if not ents:
        raise SystemExit("rom2image.py: HARD.COM not on %s" % disk)
    return fs.read_file(ents)


# --------------------------------------------------------------------------
# the checks
# --------------------------------------------------------------------------

class Fail(Exception):
    pass


def check_monitor(rom):
    if len(rom) != MONITOR_SIZE:
        raise Fail("monitor is %d bytes, not %d" % (len(rom), MONITOR_SIZE))
    crc = zlib.crc32(rom)
    if crc != ROM_CRC32:
        raise Fail("monitor CRC32 is %08x, not %08x" % (crc, ROM_CRC32))
    return "monitor %d bytes, CRC32 %08x" % (len(rom), crc)


def check_sys_image(img):
    if len(img) != 0x1E00:
        raise Fail("system image is %d bytes, not 7680" % len(img))
    if img[0:3] != CCP_HEAD:
        raise Fail("CCP head is %s, not %s"
                   % (img[0:3].hex(" "), CCP_HEAD.hex(" ")))
    if img[BDOS_ENTRY_OFF:BDOS_ENTRY_OFF + 3] != BDOS_ENTRY:
        raise Fail("BDOS entry is %s, not %s"
                   % (img[BDOS_ENTRY_OFF:BDOS_ENTRY_OFF + 3].hex(" "),
                      BDOS_ENTRY.hex(" ")))
    n = img[CBIOS_OFF_IN_IMAGE:].count(CBIOS_VEC19)
    if n != CBIOS_VEC19_COUNT:
        raise Fail("CBIOS has %d x %s, not %d"
                   % (n, CBIOS_VEC19.hex(" "), CBIOS_VEC19_COUNT))
    return ("system image 7680 bytes; CCP head %s, BDOS entry %s, CBIOS table "
            "at 0x%04X with %d x %s"
            % (CCP_HEAD.hex(" "), BDOS_ENTRY.hex(" "), CBIOS_OFF_IN_IMAGE, n,
               CBIOS_VEC19.hex(" ")))


def check_hard(hard):
    if len(hard) != HARD_SIZE:
        raise Fail("HARD.COM is %d bytes, not %d" % (len(hard), HARD_SIZE))
    off = hoff(HARD_LEN_ADDR)
    ln = hard[off] | (hard[off + 1] << 8)
    if ln != HARD_LEN:
        raise Fail("HARD.COM's length operand at 0x%04X is 0x%03X, not 0x%03X"
                   % (HARD_LEN_ADDR, ln, HARD_LEN))
    return ("HARD.COM %d bytes; embedded BIOS 0x%04X..0x%04X (%d bytes, length "
            "read from the operand at 0x%04X)"
            % (len(hard), HARD_BIOS_ADDR, HARD_BIOS_ADDR + HARD_LEN - 1,
               HARD_LEN, HARD_LEN_ADDR))


def shim_sizes(shim):
    """The five `LD C,nn / LDIR` sizes, read out of the shim itself.

    A `LD C,nn` is two bytes and its `LDIR` is two more, so this walks the pairs
    rather than trusting a hand count -- `romvec.py`'s `LENGTHS` lesson.
    """
    out = []
    for i in range(len(shim) - 3):
        if shim[i] == 0x0E and shim[i + 2] == 0xED and shim[i + 3] == 0xB0:
            out.append(shim[i + 1])
    return tuple(out)


def check_shim(shim):
    if len(shim) != SHIM_SIZE:
        raise Fail("shim is %d bytes, not %d" % (len(shim), SHIM_SIZE))
    got = shim_sizes(shim)
    if got != LDIR_SIZES:
        raise Fail("shim LDIR sizes are %s, not %s" % (got, LDIR_SIZES))
    if shim[0] != 0x21:
        raise Fail("shim does not start with `LD HL,nn`")
    hl = shim[SHIM_LEN_OPERAND] | (shim[SHIM_LEN_OPERAND + 1] << 8)
    if hl != HARD_BIOS_ADDR:
        raise Fail("shim's `LD HL,nn` is 0x%04X, not HARD.COM 0x%04X"
                   % (hl, HARD_BIOS_ADDR))
    ld = shim[SHIM_LDBC_OPERAND] | (shim[SHIM_LDBC_OPERAND + 1] << 8)
    if ld != HARD_BIOS_ADDR + SHIM_LEN_DELTA:
        raise Fail("shim's `LD BC,(nn)` is 0x%04X, not 0x%04X"
                   % (ld, HARD_BIOS_ADDR + SHIM_LEN_DELTA))
    return ("shim %d bytes at HARD.COM 0x%04X; LDIR sizes %s = %d bytes, which "
            "is CBIOS vectors 2-31"
            % (len(shim), HARD_SHIM_ADDR,
               " / ".join(str(n) for n in got), sum(got)))


def relocate_shim(shim, image_addr):
    """Point the shim's two address operands at wherever the BIOS image lands."""
    out = bytearray(shim)
    for off in (SHIM_LEN_OPERAND, SHIM_LDBC_OPERAND):
        val = image_addr + (SHIM_LEN_DELTA if off == SHIM_LDBC_OPERAND else 0)
        out[off] = val & 0xFF
        out[off + 1] = (val >> 8) & 0xFF
    return bytes(out)


# --------------------------------------------------------------------------
# the build
# --------------------------------------------------------------------------

def build(monitor, sysimg, hard):
    """Return (image, payload, notes) -- the checks run here and raise Fail."""
    notes = [
        check_monitor(monitor),
        check_sys_image(sysimg),
        check_hard(hard),
    ]

    cbios = sysimg[CBIOS_OFF_IN_IMAGE:CBIOS_OFF_IN_IMAGE + CBIOS_SIZE]
    md10 = hard[hoff(HARD_BIOS_ADDR):hoff(HARD_BIOS_ADDR) + HARD_LEN]
    shim_raw = hard[hoff(HARD_SHIM_ADDR):hoff(HARD_SHIM_ADDR) + SHIM_SIZE]
    notes.append(check_shim(shim_raw))

    md10_addr = WINDOW + MD10_OFF
    shim = relocate_shim(shim_raw, md10_addr)
    notes.append("shim relocated: `LD HL,%04Xh`, `LD BC,(%04Xh)` (was 0x%04X / "
                 "0x%04X)" % (md10_addr, md10_addr + SHIM_LEN_DELTA,
                              HARD_BIOS_ADDR, HARD_BIOS_ADDR + SHIM_LEN_DELTA))

    payload = bytearray(PAYLOAD_SIZE)
    payload[CBIOS_OFF:CBIOS_OFF + CBIOS_SIZE] = cbios
    payload[MD10_OFF:MD10_OFF + MD10_SIZE] = md10
    payload[SHIM_OFF:SHIM_OFF + SHIM_SIZE] = shim

    image = bytearray(monitor) + bytes(payload)
    return bytes(image), bytes(payload), notes


def report(monitor, payload, notes, payload_only, out):
    w = sys.stdout.write
    w("ROM 2.0 image -- docs/o1-rom-2.0.md section 2.3 (#83)\n")
    w("=" * 72 + "\n\n")
    for n in notes:
        w("  ok  %s\n" % n)
    w("\n")

    w("layout                                    size      RAM target\n")
    w("-" * 72 + "\n")
    rows = [
        ("0000-0FFF  monitor ROM (never banked)", MONITOR_SIZE, None),
        ("1000-%04X  CBIOS" % (WINDOW + CBIOS_OFF + CBIOS_SIZE - 1),
         CBIOS_SIZE, CBIOS_RAM),
        ("%04X-%04X  MD-10 BIOS image" % (WINDOW + MD10_OFF,
                                          WINDOW + MD10_OFF + MD10_SIZE - 1),
         MD10_SIZE, MD10_RAM),
        ("%04X-%04X  install / patch / jump" % (WINDOW + SHIM_OFF,
                                                WINDOW + SHIM_OFF + SHIM_SIZE - 1),
         SHIM_SIZE, None),
    ]
    for label, size, ram in rows:
        w("  %-38s  %5d B   %s\n"
          % (label, size, "0x%04X" % ram if ram else "--"))
    spare = WINDOW_SIZE - PAYLOAD_SIZE
    w("  %-38s  %5d B   the boot screen, and the new features\n"
      % ("%04X-%04X  spare" % (WINDOW + PAYLOAD_SIZE, WINDOW + WINDOW_SIZE - 1),
         spare))
    w("-" * 72 + "\n")
    w("  %-38s  %5d B\n" % ("payload (the window, 1000-1FFF)", PAYLOAD_SIZE))
    w("  %-38s  %5d B\n" % ("image (monitor + payload)", MONITOR_SIZE + PAYLOAD_SIZE))
    w("  %-38s  %5d B\n" % ("spare in the contiguous 8 KB window",
                            MONITOR_SIZE + WINDOW_SIZE
                            - MONITOR_SIZE - PAYLOAD_SIZE))
    w("\n")

    w("The payload occupies the window; *where* it is presented is the softROM's\n"
      "decision and is open (docs/o1-rom-2.0.md section 4.1a).  The monitor here\n"
      "is the stock 1.44 -- ROM 2.0's own monitor is not written yet, so this is\n"
      "a content image: it is not bootable until rom2.asm lands and calls the shim\n"
      "at %04X.\n" % (WINDOW + SHIM_OFF))

    written = payload if payload_only else (monitor + payload)
    with open(out, "wb") as fh:
        fh.write(written)
    w("\nwrote %s (%d bytes)\n" % (out, len(written)))
    w("CRC32 %08x\n" % zlib.crc32(written))


def main(argv=None):
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))

    ap = argparse.ArgumentParser(
        description="Assemble the ROM 2.0 image from the repo's own files.")
    ap.add_argument("-o", "--out", default="/tmp/rom2.rom",
                    help="where to write the image (default /tmp/rom2.rom)")
    ap.add_argument("--monitor",
                    default=os.path.join(repo, "research", "roms", "os1-144.rom"),
                    help="the monitor: 4096 bytes (default the stock 1.44)")
    ap.add_argument("--sysimd", default=os.path.join(
        repo, "research", "shipped-software", "OS1SYSD.IMD"),
        help="the shipped system disk the CBIOS comes off")
    ap.add_argument("--harddisk", default=os.path.join(
        repo, "research", "adaptec",
        "Osborne Hard Disk Control Software Version 2.01 (1984).img"),
        help="the 2.01 utilities disk HARD.COM comes off")
    ap.add_argument("--work", default="/tmp/o1rom2",
                    help="scratch directory for the de-skewed raw image")
    ap.add_argument("--payload-only", action="store_true",
                    help="write just the 3585-byte payload")
    args = ap.parse_args(argv)

    for label, path in (("monitor", args.monitor), ("system disk", args.sysimd),
                        ("HARD.COM disk", args.harddisk)):
        if not os.path.exists(path):
            raise SystemExit("rom2image.py: no %s at %s" % (label, path))
    os.makedirs(args.work, exist_ok=True)

    monitor = open(args.monitor, "rb").read()
    try:
        sysimg = read_sys_image(args.sysimd, args.work)
        hard = read_hard_com(args.harddisk)
        image, payload, notes = build(monitor, sysimg, hard)
    except Fail as exc:
        raise SystemExit("rom2image.py: ANCHOR MOVED -- %s\n"
                         "The image would not be the one the design describes. "
                         "Fix the anchor or the design first." % exc)

    report(monitor, payload, notes, args.payload_only, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())

