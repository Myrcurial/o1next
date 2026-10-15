#!/usr/bin/env python3
"""md10reloc.py -- re-relocate the MD-10's operating system to its load address.

WHY THIS EXISTS
    `research/adaptec/md10-system/*.bin` are systems the vendor's own
    `PREP.COM` (option 3) wrote, captured off a drive -- see
    `docs/md10-system.md`.  A capture's addresses may sit at the wrong base,
    and *which* base is a property of the run, not a constant.

    `HARD.COM` reads the system to `0xC200` (11 blocks from LBA 5) and patches
    page zero to `JP 0CA06h`, so the CCP belongs at `0xC200` and the BDOS at
    `0xCA00` -- which is also the only placement that fits, since the BDOS ends
    exactly where the MD-10 BIOS starts at `0xD800`.  A capture relocated
    0x100 high therefore has its CCP's first instruction at `JP 0C5C8h`, and
    `0xC5C8` is the *middle* of a `CP 20h`.  `0xC4C8`, exactly 0x100 lower, is
    `LD SP,0C8C5h` followed by `PUSH BC / LD A,C / RRA x4 / AND 0Fh / LD E,A /
    LD C,0Dh / CALL 5` -- the CP/M CCP's own `COMMAND:` entry, ending in the
    BDOS "reset disk" call.  Relocated 0x100 high, the CCP jumps into the
    middle of an instruction, runs garbage and warm boots, which is why the
    guest re-read the system 1 303 times in 150 emulated seconds and never
    prompted (#198).

    **Two captures, two different bases (measured 2026-10-14).** The
    two-partition PYXIS13 capture in `md10-system/` carries base `0xC300` and
    does need the 0x100 correction.  The three-partition PYXIS27 capture
    (`md10-os-p27.bin`) carries base `0xC200` -- it is **already correct**, and
    its CCP entry is `JP 0C4C8h` with `0x31` (`LD SP,nn`) at the target.  So
    the shift is derived from each capture, never assumed; the old code
    subtracted a constant `--shift` whatever the delta was, which silently
    broke an already-correct capture.

    **A capture can also sit *below* the load base, and that is not fatal
    (measured 2026-10-15).** `md10prep.sh 1200,8,18 eq11` writes base `0xB900`
    -- nine pages low -- and `md10prep.sh 321,8,18 eq11` writes `0xC100`, one
    page low, while `eq3`/`eq6` and the standard partition options all come out
    at `0xC200`.  `PREP.COM` does not store a base: it relocates with a bit-map
    walk (`add a,<page>` at `2A9E`, self-patched) and *computes* the page as
    `*(0x0002) - ceil(size/0x100)`, where `*(0x0002)` is the top of the memory it
    is running in and `size` is accumulated over its own 24-byte drive-table
    records (`0x277C`-`0x2830`); the CCP is then placed `0x16` pages below that
    and the BDOS `+8` above the CCP (`0x292F`-`0x295F`).  So the page is a
    property of the *run*, and it moves as the layout grows -- which is why the
    bigger layouts miss.

    The correction is a page *add*, so it works in either direction: a capture
    below the load base is shifted **up** by the same arithmetic that shifts one
    above it **down**.  And the load base is not a matter of taste -- the image
    is 0x1600 bytes and the MD-10 BIOS starts at 0xD800, so the only placement
    that fits is `0xD800 - 0x1600 = 0xC200`.  That is the check: the two regions
    must agree on the shift, and the CCP's entry must land on `LD SP,nn`.

WHY THE CORRECTION IS MEASURED, NOT GUESSED
    `HARDCCP.SPR` and `HARDBDOS.SPR` on the 2.01 utilities disk are the
    *relocatable* source `PREP.COM` relocates from (each carries a 0x100-byte
    header; the body follows).  Comparing each SPR body against the matching
    half of the captured image shows that the two differ **only in the high
    byte of relocated address operands**, and that the difference is a single
    constant per file:

        CCP    232 differing bytes, every delta 0xC3
        BDOS   558 differing bytes, every delta 0xCB (plus 4 stamped bytes)

    0xC3 and 0xCB are page deltas, and they *are* the relocation's base:
    `PREP.COM` added `0xC300`/`0xCB00` where the load addresses are
    `0xC200`/`0xCA00`.  So the image is one uniform relocation of the SPRs, and
    moving it to the load base is exact -- no disassembly and no guesswork.
    The PYXIS27 capture shows `0xC2`/`0xCA`, i.e. it was relocated to the load
    base already and needs no change at all.  (The 4 BDOS bytes that are not
    the constant are the BDOS serial number, which `PREP.COM` stamps; they are
    left alone.)

HOW IT IS DRIVEN
    tools/research/md10reloc.py --out /tmp/md10/md10-os.bin
    tools/research/md10reloc.py --os .../md10-os-p27.bin --out /tmp/md10/os.bin
    tools/research/md10reloc.py --out ... --dry-run

    The shift is **derived per region** from the measured delta and that
    region's load base (`pages = delta - base>>8`), so an already-correct
    capture is left alone instead of being shifted.  --shift overrides the
    derivation when a capture needs something unusual.  --dry-run prints what
    it would change and writes nothing.

    It then **validates before it writes**: the CCP entry must land on
    `LD SP,nn` (0x31).  If it does not, the tool refuses (exit 1) rather than
    writing an image it knows is wrong -- which is what the old version did
    while only printing a warning.

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

# Where `HARD.COM` puts each half.  It reads the system to 0xC200 (11 blocks
# from LBA 5) and patches page zero to `JP 0CA06h`, so the CCP belongs at
# 0xC200 and the BDOS at +0x800 -- which is also the only placement that fits,
# since the BDOS ends exactly where the MD-10 BIOS starts at 0xD800.
CCP_BASE = 0xC200
BDOS_BASE = CCP_BASE + CCP_LEN          # 0xCA00


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
    regions = (("CCP", 0x000, CCP_LEN, CCP_BASE, ccp),
               ("BDOS", CCP_LEN, len(captured), BDOS_BASE, bdos))

    out = bytearray(captured)
    total = 0
    seen = []
    for label, lo, hi, base, body in regions:
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
        # The delta *is* the relocation's page, so the image's base is
        # `delta << 8` and the shift to the load base is the difference.
        # Deriving it -- rather than assuming 0x100 -- is the point: an
        # already-correct capture yields 0 pages and is left alone.
        if args.shift is None:
            pages = delta - (base >> 8)
        else:
            pages = args.shift // 0x100
            print("  --shift override: 0x%X" % args.shift)
        print("  relocation delta %02X (a base 0x%04X) -> load base 0x%04X: "
              "%+d page(s) (%s)"
              % (delta, delta << 8, base, pages,
                 "down" if pages > 0 else "up" if pages < 0 else "none"))
        seen.append((label, pages))
        if pages == 0:
            print("  already at its load base -- nothing to change")
            continue
        # One page *add* either way.  The capture is `body` relocated to
        # `delta << 8` and the load base is `base`, so every relocated operand
        # high byte moves by `(base >> 8) - delta` -- down when the capture is
        # above the load base, up when it is below.  `out[i] = captured[i] -
        # pages` is that sum, so it needs no sign test.
        n = 0
        for i in range(lo, hi):
            j = i - lo
            if j < len(body) and captured[i] != body[j] and \
                    ((captured[i] - body[j]) & 0xFF) == delta:
                out[i] = (captured[i] - pages) & 0xFF
                n += 1
        total += n
        print("  %d bytes re-relocated" % n)

    # The regions are one image, so they must agree about the shift.  They are
    # relocated by the same page in every capture measured, so a disagreement
    # means the delta derivation is wrong for one of them -- and the CCP/BDOS
    # placement is a fixed 8 pages apart (`PREP.COM`'s `add a,008h` at 0x295D),
    # so a half-corrected image is a warm-boot loop rather than a crash.
    if len({p for _, p in seen}) > 1:
        print("  the regions disagree about the shift (%s); refusing to guess"
              % ", ".join("%s %+d" % t for t in seen))
        return 1

    if args.dry_run:
        print("dry run: nothing written (%d bytes would change)" % total)
        return 0

    # Validate before writing: the CCP's entry must land on a real instruction.
    # CP/M's CCP entry is `JP COMMAND`, and COMMAND opens with `LD SP,nn` (0x31).
    tgt = out[1] | (out[2] << 8)
    where = tgt - CCP_BASE
    op = out[where] if 0 <= where < len(out) else None
    print("CCP entry JP -> 0x%04X, byte there %s" %
          (tgt, "0x%02X" % op if op is not None else "out of range"))
    if op != 0x31:
        print("  ERROR: not `LD SP,nn` -- the CCP entry does not look like "
              "CP/M's COMMAND, so this image would warm-boot for ever (#198). "
              "Refusing to write it; check the delta, or pass --shift.")
        return 1

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
    p.add_argument("--shift", default=None, type=lambda s: int(s, 0),
                   metavar="N", help="override the derived shift (default: "
                                     "derive it per region from the capture)")
    p.add_argument("--dry-run", action="store_true",
                   help="report the deltas and write nothing")
    args = p.parse_args(argv[1:])
    return build(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))

