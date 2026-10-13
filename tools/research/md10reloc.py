#!/usr/bin/env python3
"""md10reloc.py -- re-relocate the MD-10's operating system to its load address.

WHY THIS EXISTS
    `research/adaptec/md10-system/md10-os.bin` is the system the vendor's own
    `PREP.COM` (option 3) wrote, captured off a drive -- see
    `docs/md10-system.md`.  Its addresses are relocated **0x100 bytes too
    high**, and that is the whole of #198's "the system boots but never reaches
    its prompt".

    `HARD.COM` reads the system to `0xC200` (11 blocks from LBA 5) and patches
    page zero to `JP 0CA06h`, so the CCP belongs at `0xC200` and the BDOS at
    `0xCA00` -- which is also the only placement that fits, since the BDOS ends
    exactly where the MD-10 BIOS starts at `0xD800`.  But the captured CCP's
    first instruction is `JP 0C5C8h`, and `0xC5C8` is the *middle* of a
    `CP 20h`.  `0xC4C8`, exactly 0x100 lower, is `LD SP,0C8C5h` followed by
    `PUSH BC / LD A,C / RRA x4 / AND 0Fh / LD E,A / LD C,0Dh / CALL 5` --
    the CP/M CCP's own `COMMAND:` entry, ending in the BDOS "reset disk"
    call.  Relocated 0x100 high, the CCP jumps into the middle of an
    instruction, runs garbage and warm boots, which is why the guest re-read
    the system 1 303 times in 150 emulated seconds and never prompted.

WHY THE CORRECTION IS MEASURED, NOT GUESSED
    `HARDCCP.SPR` and `HARDBDOS.SPR` on the 2.01 utilities disk are the
    *relocatable* source `PREP.COM` relocates from (each carries a 0x100-byte
    header; the body follows).  Comparing each SPR body against the matching
    half of the captured image shows that the two differ **only in the high
    byte of relocated address operands**, and that the difference is a single
    constant per file:

        CCP    232 differing bytes, every delta 0xC3
        BDOS   558 differing bytes, every delta 0xCB (plus 4 stamped bytes)

    0xC3 and 0xCB are page deltas: `PREP.COM` added `0xC300`/`0xCB00` where
    the load addresses are `0xC200`/`0xCA00`.  So the image is one uniform
    relocation of the SPRs at a base 0x100 too high, and re-applying it at the
    right base is exact -- no disassembly and no guesswork.  (The 4 BDOS bytes
    that are not the constant are the BDOS serial number, which `PREP.COM`
    stamps; they are left alone.)

HOW IT IS DRIVEN
    tools/research/md10reloc.py --out /tmp/md10/md10-os.bin
    tools/research/md10reloc.py --out ... --shift 0x100 --dry-run

    --shift defaults to 0x100, the measured error.  --dry-run prints what it
    would change and writes nothing.  The deltas are derived from the files
    each run, so if a future capture is relocated correctly this tool says so
    (delta 0, nothing to do) rather than silently corrupting it.

    The output is what `tools/research/md10drive.py --os` lays on a drive:

        tools/research/md10reloc.py --out /tmp/md10/md10-os.bin
        tools/research/md10drive.py --out /tmp/md10/hd.chd \\
            --os /tmp/md10/md10-os.bin

    The captured artifact in `research/` is an archive and is never modified.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools"))

import cpmfs  # noqa: E402  (in-repo, stdlib-only, the archive's own reader)

UTILS = os.path.join(REPO, "research", "adaptec",
                     "Osborne Hard Disk Control Software Version 2.01 (1984).img")
CAPTURED = os.path.join(REPO, "research", "adaptec", "md10-system", "md10-os.bin")

CCP_LEN = 0x800          # the CCP is 0x800 bytes; the BDOS starts at +0x800
SPR_HEADER = 0x100       # every .SPR carries a 0x100-byte header


def spr_body(name):
    """The body of a .SPR on the 2.01 utilities disk, with its 0x100 header off."""
    cpm = cpmfs.CPM(UTILS, 'osb1sssd')
    user, base, ext = cpmfs.parse_spec("0:" + name)
    for (u, n, x), ents in cpm.files().items():
        if u == user and n.strip() == base.strip() and x.strip() == ext.strip():
            return cpm.read_file(ents)[SPR_HEADER:]
    sys.exit("md10reloc.py: %s not found on %s" % (name, UTILS))


def relocate_delta(captured, body):
    """The constant page delta the image carries against this SPR body.

    Only *high bytes* of relocated operands differ, so every differing byte
    shows the same delta; the most common one is the relocation's.  Returning
    the whole histogram lets the caller see when that assumption is false.
    """
    hist = {}
    for i in range(min(len(captured), len(body))):
        if captured[i] != body[i]:
            d = (captured[i] - body[i]) & 0xFF
            hist[d] = hist.get(d, 0) + 1
    if not hist:
        return 0, hist
    return max(hist.items(), key=lambda kv: kv[1])[0], hist


def build(args):
    captured = open(args.os, "rb").read()
    ccp, bdos = spr_body("HARDCCP.SPR"), spr_body("HARDBDOS.SPR")
    regions = (("CCP", 0x000, CCP_LEN, ccp),
               ("BDOS", CCP_LEN, len(captured), bdos))

    out = bytearray(captured)
    total = 0
    for label, lo, hi, body in regions:
        delta, hist = relocate_delta(captured[lo:hi], body)
        spread = {k: v for k, v in hist.items() if v > 4}
        print("%s: %d differing bytes, deltas %s" %
              (label, sum(hist.values()),
               ", ".join("%02X x%d" % (k, v) for k, v in sorted(spread.items()))))
        if delta == 0:
            print("  no relocation found -- nothing to do for this region")
            continue
        if len(spread) > 1:
            print("  more than one delta above 4 occurrences; refusing to guess")
            return 1
        # The differing byte is the *page* number of the address, so an
        # address shift of 0x100 is one unit off the byte.
        pages = args.shift // 0x100
        print("  relocation delta %02X (a base 0x%04X); re-applying %d page(s) lower"
              % (delta, delta << 8, pages))
        n = 0
        for i in range(lo, hi):
            j = i - lo
            if j < len(body) and captured[i] != body[j] and \
                    ((captured[i] - body[j]) & 0xFF) == delta:
                out[i] = (captured[i] - pages) & 0xFF
                n += 1
        total += n
        print("  %d bytes re-relocated" % n)

    if args.dry_run:
        print("dry run: nothing written (%d bytes would change)" % total)
        return 0

    # Sanity check: the CCP's entry must land on a real instruction.  CP/M's
    # CCP entry is `JP COMMAND`, and COMMAND opens with `LD SP,nn` (0x31).
    tgt = out[1] | (out[2] << 8)
    where = tgt - 0xC200
    op = out[where] if 0 <= where < len(out) else None
    print("CCP entry JP -> 0x%04X, byte there %s" %
          (tgt, "0x%02X" % op if op is not None else "out of range"))
    if op != 0x31:
        print("  warning: not `LD SP,nn` -- the CCP entry does not look like "
              "CP/M's COMMAND; check the delta before using this image")

    with open(args.out, "wb") as f:
        f.write(out)
    print("wrote %s (%d bytes, %d re-relocated)" % (args.out, len(out), total))
    return 0


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", required=True, help="the re-relocated image to write")
    p.add_argument("--os", default=CAPTURED, metavar="PATH",
                   help="the captured O/S image (default: %s)" %
                        os.path.relpath(CAPTURED, REPO))
    p.add_argument("--shift", default=0x100, type=lambda s: int(s, 0),
                   metavar="N", help="how far to move addresses down (default 0x100)")
    p.add_argument("--dry-run", action="store_true",
                   help="report the deltas and write nothing")
    args = p.parse_args(argv[1:])
    return build(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

