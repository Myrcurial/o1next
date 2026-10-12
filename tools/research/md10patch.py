#!/usr/bin/env python3
"""md10patch.py -- patch a file inside a raw Osborne 1 SD image, by name.

WHY THIS EXISTS
    #178's drive-table question is settled by running `MD10.COM` -- the MD-10
    drive-table editor -- editing one field and diffing `DRIVETBL.DAT`. The
    editor itself needs no hardware: it only reads and writes that file. But
    `MD10.COM` refuses to start without an ACB-4000 answering on ports 30h-33h
    ("Interface board or software not addressed properly"), and MAME cannot
    emulate the controller, so the presence check has to be stepped over.

    The check is one instruction. At 0x0EB9 the program does

        CALL 15AFh        ; controller-address probe, result in (2FFBh)
        JR   Z, 0EE2h     ; one controller on-line -> load DRIVETBL.DAT
        JP   NC,1162h     ; ... else the format/password path
        ...

    and 0x15AF opens with `LD A,(2FFBh) / DEC A` -- so patching those three
    bytes to `LD A,1 / NOP` makes the "exactly one controller on-line" test
    succeed. Nothing else is touched: the geometry code, the editor and the
    file I/O are the vendor's own bytes. See docs/harddisk-decision.md 7.2.

USAGE
    md10patch.py IN.img OUT.img FILE OFFSET:HEX [OFFSET:HEX ...]

    OFFSET is a file offset inside FILE (so for a .COM, mem-0x100), HEX is the
    replacement bytes. The image must be raw 40x10x256B FM single-sided
    (102400 bytes); `tools/research/o1raw2imd.py` then wraps the result for
    MAME. The archive image is never modified -- always write to a copy.
"""
import sys

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
sys.path.insert(0, __import__("os").path.join(
    __import__("os").path.dirname(__import__("os").path.abspath(__file__)), ".."))
from cpmfs import CPM                                    # noqa: E402


def raw_offset(fs, blocks, x):
    """Raw-image offset of byte `x` of a file whose block list is `blocks`."""
    bs, seclen, nsec = fs.blocksize, fs.seclen, fs.blocksize // fs.seclen
    block, off = divmod(x, bs)
    sec, byte = divmod(off, seclen)
    logical = fs.bootsect + blocks[block] * nsec + sec
    track, s = divmod(logical, fs.sectrk)
    phys = track * fs.sectrk + fs.skewtab[s]
    return phys * seclen + byte


def find(fs, name):
    base, ext = name.split(".")
    for e in fs.entries:
        if e["name"].rstrip() == base.upper() and e["ext"].rstrip() == ext.upper():
            return e
    sys.exit(f"md10patch.py: {name} not found in the image")


def main(argv):
    if len(argv) < 4:
        sys.exit(__doc__)
    src, dst, fname = argv[0], argv[1], argv[2]
    raw = bytearray(open(src, "rb").read())
    fs = CPM(src, "osb1sssd")
    ent = find(fs, fname)
    blocks, size = ent["blocks"], ent["rc"] * 128
    for spec in argv[3:]:
        off_s, hex_s = spec.split(":", 1)
        off = int(off_s, 0)
        new = bytes.fromhex(hex_s)
        if off + len(new) > size:
            sys.exit(f"md10patch.py: patch at {off:#x} runs past {fname} ({size} B)")
        for i, b in enumerate(new):
            raw[raw_offset(fs, blocks, off + i)] = b
        print(f"{fname} +{off:#05x} ({off:#05x}) <- {new.hex(' ')}")
    open(dst, "wb").write(bytes(raw))
    print(f"wrote {dst}")


if __name__ == "__main__":
    main(sys.argv[1:])
