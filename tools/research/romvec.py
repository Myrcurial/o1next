#!/usr/bin/env python3
"""romvec.py -- decode the Osborne 1 monitor ROM's jump table, and check it
against the source it was built from.

WHY THIS EXISTS
    #83 wants a ROM 2.0, and the one thing a replacement ROM must not break is
    the *interface* the CBIOS and third-party programs already call.  That
    interface is a table of 3-byte `JMP`s at address 0x0100 -- `ROMVEC = 100h`
    in `occtxt6.ast`, "Start of rom vector" -- and the CBIOS reaches it by
    arithmetic rather than by a table pointer (see "the contract" below).

    Before designing on top of it, the table has to be *enumerated from the
    shipped bytes* and shown to be the table the source describes.  That is what
    this tool does, and it is the evidence for `docs/o1-rom-2.0.md` section 3.

WHAT IT FOUND (2026-10-13, #83)
    53 entries, 0x0100-0x019E, 159 bytes.  The table ends exactly where the
    source's `IMSG:` sign-on message begins (0x019F), which is the independent
    confirmation that 53 is the whole table and not a guess: the first byte of
    `IMSG` is `'Z'-40h` = 0x1A, and 0x019F holds 0x1A.

    Entries 0-33 mirror the CBIOS's own jump table (`occbio15.asm`) -- and are
    reached by it -- and 34-52 are the ROM's own disk, SuperCalc and IEEE
    entry points.  One entry is a stub: index 9, `RET / NOP / NOP`, "SELECT
    DISK", because the CBIOS supplies SELDSK itself.

    Two things do **not** line up, and both are recorded rather than smoothed
    over (see docs/o1-rom-2.0.md section 3.3):
      * indices 10, 11, 12 and 16 carry the ROM's own labels (READ / WRITE /
        RADR / SENDEN) where the CBIOS's table has SETTRK / SETSEC / SETDMA /
        SECTRN -- the CBIOS implements those itself and never calls the ROM
        for them, so nothing is broken;
      * `occtxt6.ast` publishes `BSTTRK = 10*3`, `BSTSEC = 11*3`,
        `BSTDMA = 12*3`, `BSECTR = 16*3` to match that *assumed* alignment, and
        **no CBIOS source uses any of them** -- nor `BIOCAL`, the macro that
        would.  The constants are dead code with the wrong numbers.

THE CONTRACT (why the numbering is not negotiable)
    `occbio35.asm`'s `ROMCDE` derives the ROM vector from the CBIOS's *own
    address*: it pops the return address, subtracts 3, and forces the high byte
    to `high(ROMVEC)` = 0x01.  So CBIOS vector N, sitting at `BIOS + 3N`,
    selects ROM vector N -- and that only works while `BIOS`'s low byte is 0x00
    (0xE100).  `occbio15.asm` says as much: "NOTE: ROM jump vector must match
    CBIOS vector".

    Two call sites are hard-coded and are the ones a replacement ROM must
    redirect: `occbio55.asm` warm boot does `LDK DE,ROMVEC+3*1`, and
    `occbio65.asm`'s sector transfer does `LDK HL,ROMVEC+3*13`.

Usage:
    romvec.py [ROM] [--source ASM]

Defaults to research/roms/os1-144.rom and the 1.44 source beside it.  Exits
non-zero if the binary's opcode sequence and the source's disagree.
"""
import os
import re
import sys

ROMVEC = 0x0100          # occtxt6.ast: "Start of rom vector"

# The CBIOS's jump table order, from occbio15.asm ("the order of these jump
# cannot be modified").  Used only to label the first 34 ROM vectors; the ROM's
# own source labels are printed alongside so a disagreement is visible.
CBIOS_VECTORS = [
    "CBOOT", "WBOOT", "CONST", "CONIN", "CONOUT", "LIST", "PUNCH", "READER",
    "HOME", "SELDSK", "SETTRK", "SETSEC", "SETDMA", "READ", "WRITE", "LISTST",
    "SECTRN", "RRI", "ROMJMP", "FMTJ", "SBAUD",
    "IEB1C/IE.CO", "IEB2C/IE.SI", "IEB3C/IE.GTS", "IEB4C/IE.TC",
    "IEB5C/IE.OIM", "IEB6C/IE.ODM", "IEB7C/IE.IDM", "IEB8C/IE.PP",
    "(extension 1)", "(extension 2)", "(extension 3)", "ACICTL", "ACISTAT",
]

# The two vectors the CBIOS hard-codes, with the file that does it.
HARDCODED = {
    1: "occbio55.asm warm boot: LDK DE,ROMVEC+3*1 -- the system reload",
    13: "occbio65.asm sector transfer: LDK HL,ROMVEC+3*13 -- one sector R/W",
}

OPCODES = {0xC3: "JMP", 0xC9: "RET", 0xCD: "CALL", 0x00: "NOP"}


# Bytes each instruction occupies, so the source's lines can be grouped into
# the table's 3-byte vector slots.  This matters: slot 9 is written as three
# separate lines (`RET` / `NOP` / `NOP`), and counting lines instead of bytes
# shifts every label after it by two -- which is exactly the bug this grouping
# exists to prevent.
LENGTHS = {"JMP": 3, "CALL": 3, "RET": 1, "NOP": 1}


def parse_source(path):
    """Group the source's table lines into 3-byte vector slots, in order."""
    lines = open(path, "r", encoding="latin-1").read().split("\n")
    try:
        start = next(i for i, l in enumerate(lines)
                     if re.match(r"\s*ORG\s+100h\b", l, re.I))
    except StopIteration:
        raise SystemExit(f"romvec.py: no 'ORG 100h' in {path}")
    out, slot, used = [], [], 0
    for line in lines[start + 1:]:
        body = line.split(";")[0]
        toks = [t for t in re.split(r"[\t ]+", body.strip()) if t]
        if not toks:
            continue
        label = ""
        if toks[0].endswith(":"):
            label = toks.pop(0)[:-1]
        if not toks:
            continue
        mnem = toks[0].upper()
        if mnem not in LENGTHS:
            break                       # IMSG: / TITLE -- the table is over
        comment = line.split(";", 1)[1].strip() if ";" in line else ""
        slot.append((label, mnem, comment))
        used += LENGTHS[mnem]
        if used == 3:
            out.append(slot)
            slot, used = [], 0
        elif used > 3:
            raise SystemExit(f"romvec.py: {line!r} overruns its 3-byte vector")
    return out


def decode_binary(data, count):
    """Decode `count` 3-byte vectors starting at ROMVEC."""
    out = []
    for i in range(count):
        off = ROMVEC + 3 * i
        b = data[off:off + 3]
        if len(b) < 3:
            raise SystemExit(f"romvec.py: ROM is too short for {count} vectors")
        op = b[0]
        mnem = OPCODES.get(op)
        target = None
        if mnem is None:
            mnem = f"DB {op:02X}h"
        elif op in (0xC3, 0xCD):
            target = b[1] | (b[2] << 8)
        out.append((off, mnem, target, b))
    return out


def main(argv):
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    rom = os.path.join(repo, "research", "roms", "os1-144.rom")
    src = os.path.join(repo, "research", "source-code", "BIOS-144-source",
                       "rom144.asm")
    args = [a for a in argv[1:] if not a.startswith("--")]
    if args:
        rom = args[0]
    if "--source" in argv:
        src = argv[argv.index("--source") + 1]

    data = open(rom, "rb").read()
    source = parse_source(src)
    binary = decode_binary(data, len(source))

    print(f"ROM        {os.path.relpath(rom, repo)}  ({len(data)} bytes)")
    print(f"Source     {os.path.relpath(src, repo)}  "
          f"(table declared at ORG 100h)")
    print(f"Table      {len(source)} entries at 0x{ROMVEC:04X}, "
          f"3 bytes each -> ends 0x{ROMVEC + 3 * len(source) - 1:04X}")
    print()

    hdr = (f"{'#':>3}  {'addr':>5}  {'target':>6}  {'ROM source':<12} "
           f"{'label':<9} {'CBIOS vector':<14} comment")
    print(hdr)
    print("-" * len(hdr))
    bad = 0
    for i, (slot, (off, bmnem, target, raw)) in \
            enumerate(zip(source, binary)):
        mnem = "/".join(m for _, m, _ in slot)
        first = slot[0][1]
        label = next((l for l, _, _ in slot if l), "")
        comment = next((c for _, _, c in slot if c), "")
        cb = CBIOS_VECTORS[i] if i < len(CBIOS_VECTORS) else ""
        tgt = f"0x{target:04X}" if target is not None else "  --  "
        flag = ""
        if first != bmnem:
            flag = f"  <<< source says {first}, ROM holds {bmnem}"
            bad += 1
        note = HARDCODED.get(i)
        if note:
            comment = (comment + "  " if comment else "") + f"[{note}]"
        print(f"{i:>3}  0x{off:04X}  {tgt}  {mnem:<12} {label:<9} {cb:<14} "
              f"{comment}{flag}")

    print()
    nxt = ROMVEC + 3 * len(source)
    print(f"first byte after the table  0x{nxt:04X} = 0x{data[nxt]:02X}  "
          f"(the source's next label is IMSG:, whose first byte is "
          f"0x1A = 'Z'-40h)")
    stubs = [i for i, (_, m, _, _) in enumerate(binary) if m == "RET"]
    print(f"stub vectors (RET)          {stubs}")
    print(f"opcode disagreements        {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
