#!/usr/bin/env python3
"""hardbios.py -- read the MD-10 hard-disk BIOS, and audit where its tables come from.

WHY THIS EXISTS
    #178 owes exactly one thing: the *numeric* DPB (SPT/BSH/BLM/EXM/DSM/DRM/AL0/
    AL1/CKS/OFF) that the MD-10 driver builds at run time.  `docs/harddisk-
    decision.md` 7.2 read the drive table; 7.3 records the DPB mechanism and why
    the archive cannot supply the numbers.  This tool is what produced that
    answer, so the answer is reproducible instead of being a claim:

      jump   -- print the CP/M 2.2 BIOS jump table with every target resolved,
                and the SELDSK DPH construction that follows from it.
      audit  -- find every writer of the low-RAM table block.  This is the
                negative result: *nothing* in the archive writes `0x055E` (the
                per-drive type byte) or `0x056E` (the 24-byte descriptor table).

    Reading the overlay needs care.  `HARDBIOS.SPR` is a *relocatable* image: its
    jump-table operands and its internal `JP`/`CALL` targets are offsets from the
    jump table, not absolute addresses.  A linear disassembler drifts out of sync
    through the data and invents instructions -- which is how `0xE21A` first read
    as garbage.  `jump` resolves them the way the loader does.

WHAT IT FOUND (2026-10-12, #178)
    SELDSK sits at file offset `0x1D5` (the jump table's operand `0x00D5` + the
    table base `0xE100`, i.e. `0xE1D5` in the address space 7.1 quotes) and returns
    a DPH built as `0x056E + type*24 + 8`, where `type` is the per-drive byte at
    `0x055E + drive`.  The DPB pointer is at DPH+10 -- the standard CP/M DPH
    layout -- and the driver dereferences it (file offset `0x393`), so the DPB is
    a real CP/M 2.2 DPB.  But no archived file initialises `0x055E`/`0x056E`: not
    the BIOS, not the BDOS/CCP overlays, not `MD10.COM`/`MD20.COM`, not the
    installer.  And the MD utilities disk is a *data* disk -- its system tracks
    are all `0xE5` -- so the archive holds no MD-10 system image.  The numbers are
    therefore not in the files we have; see `docs/harddisk-decision.md` 7.3.

USAGE
    hardbios.py jump  SPR_FILE             jump table + SELDSK (relocatable image)
    hardbios.py jump  IMAGE --hex          ... for an absolute Intel-HEX image
    hardbios.py audit SPR_FILE [DIR ...]   who writes the low-RAM tables

    The MD utilities disk is a raw `.img`; extract the overlays with
        tools/cpmfs.py 'research/adaptec/MD Utilities ... .img' osb1sssd get 0:HARDBIOS.SPR /tmp/
"""
import glob
import os
import sys

# The CP/M 2.2 BIOS jump table, in order.
JUMP = ("BOOT", "WBOOT", "CONST", "CONIN", "CONOUT", "LIST", "PUNCH", "READER",
        "HOME", "SELDSK", "SETTRK", "SETSEC", "SETDMA", "READ", "WRITE",
        "LISTST", "SECTRAN")


def load_hex(path):
    """Intel HEX -> (bytes, origin).  An absolute image: operands are addresses."""
    data, base = {}, 0
    for line in open(path):
        line = line.strip()
        if not line.startswith(':'):
            continue
        b = bytes.fromhex(line[1:])
        n, addr, typ = b[0], (b[1] << 8) | b[2], b[3]
        if typ == 0:
            for i in range(n):
                data[base + addr + i] = b[4 + i]
        elif typ == 1:
            break
        elif typ == 2:
            base = int.from_bytes(b[4:6], 'big') << 4
        elif typ == 4:
            base = int.from_bytes(b[4:6], 'big') << 16
    lo = min(data)
    return bytes(data[a] for a in range(lo, max(data) + 1)), lo


def jump(buf, reloc):
    """Print the jump table.  `reloc` = operands are offsets from the table.

    Returns the file offset of SELDSK's target, which is where `seldsk` starts.
    """
    off = 0x100 if reloc else 0x00          # the table sits 0x100 into a .SPR
    print('=== BIOS jump table (file offset 0x%03X) ===' % off)
    target = None
    for i, name in enumerate(JUMP):
        a = off + i * 3
        if a + 3 > len(buf) or buf[a] != 0xC3:
            print('  %-8s 0x%03X: not a JP' % (name, a))
            continue
        tgt = buf[a + 1] | (buf[a + 2] << 8)
        if reloc:
            where = '0x%03X (file)' % (off + tgt)
            if name == 'SELDSK':
                target = off + tgt
        else:
            where = '0x%04X' % tgt
            if name == 'SELDSK':
                target = tgt
        print('  %-8s 0x%03X: JP -> %s' % (name, a, where))
    return target


def seldsk(buf, file_off):
    """Walk SELDSK far enough to show the DPH it builds.

    The two operands that matter are `LD BC,nn` (the per-drive type-byte table)
    and `LD DE,nn` (the 24-byte descriptor table); the arithmetic between them is
    `type * 8`, then three times more via two `ADD HL,DE`, i.e. `type * 24`.

    Instructions are stepped by their real length.  A byte scan for 0x01/0x11
    finds them inside other instructions' operands -- `LD (0180h),A` is
    `32 80 01`, whose trailing 0x01 reads as `LD BC,016F` if you do not decode.
    """
    LEN = {0x01: 3, 0x11: 3, 0x21: 3, 0x22: 3, 0x32: 3, 0x3A: 3, 0xC3: 3,
           0xCD: 3, 0xF2: 3, 0xD2: 3, 0xFE: 2, 0xE6: 2, 0x16: 2, 0x3E: 2,
           0x06: 2, 0x0E: 2, 0x10: 2, 0x18: 2, 0x20: 2, 0x28: 2, 0x30: 2,
           0x38: 2, 0xD3: 2, 0xDB: 2, 0xED: 2}
    print()
    if file_off is None or not (0 <= file_off < len(buf)):
        print('=== SELDSK: no target found in the jump table ===')
        return
    print('=== SELDSK at file offset 0x%03X ===' % file_off)
    p, steps = file_off, 0
    while p < len(buf) and steps < 80:
        steps += 1
        op = buf[p]
        if op == 0xC9:
            print('  0x%03X: C9     RET           <- returns HL = the DPH' % p)
            return
        if op in (0x01, 0x11) and p + 2 < len(buf):
            nn = buf[p + 1] | (buf[p + 2] << 8)
            if op == 0x01:
                print('  0x%03X: 01 %02X %02X  LD BC,%04X  <- per-drive type byte table'
                      % (p, buf[p + 1], buf[p + 2], nn))
            elif nn == 0x0008:
                print('  0x%03X: 11 08 00  LD DE,0008  <- += 8: the DPH within the entry'
                      % p)
            else:
                print('  0x%03X: 11 %02X %02X  LD DE,%04X  <- 24-byte descriptor table'
                      % (p, buf[p + 1], buf[p + 2], nn))
        elif op == 0x87:
            print('  0x%03X: 87     ADD A,A       <- type * 8' % p)
        elif op == 0x19:
            print('  0x%03X: 19     ADD HL,DE     <- accumulate toward type * 24' % p)
        p += LEN.get(op, 1)


def audit(paths, lo=0x0500, hi=0x0700):
    """Every writer of a low-RAM address in [lo, hi).

    LD (nn),A = 32 nn nn ; LD (nn),HL = 22 nn nn ; LD (nn),BC/DE = ED 43/53 nn nn.
    This is the search that returned the negative result: the DPH/DPB tables at
    0x055E and 0x056E have no writer anywhere in the archive.
    """
    print('=== writers of 0x%04X-0x%04X ===' % (lo, hi))
    total, table = 0, []
    for f in paths:
        if not os.path.isfile(f):
            continue
        d = open(f, 'rb').read()
        hits = []
        for i in range(len(d) - 3):
            nn = None
            if d[i] in (0x32, 0x22):
                nn = d[i + 1] | (d[i + 2] << 8)
            elif d[i] == 0xED and d[i + 1] in (0x43, 0x53):
                nn = d[i + 2] | (d[i + 3] << 8)
            if nn is not None and lo <= nn < hi:
                hits.append('%04X@0x%X' % (nn, i))
        if hits:
            total += len(hits)
            print('  %-18s %s' % (os.path.basename(f), ' '.join(sorted(set(hits)))))
            if any(h.startswith(('055E', '056E')) for h in hits):
                table.append(os.path.basename(f))
    if not total:
        print('  none')
    print()
    if table:
        print('  0x055E / 0x056E writers: %s' % ', '.join(table))
    else:
        print('  0x055E / 0x056E writers: NONE -- no archived file initialises the')
        print('  per-drive type byte or the 24-byte descriptor table, so the DPB')
        print('  cannot be read from the files we hold.')


def main(argv):
    if len(argv) < 2:
        print(__doc__.strip())
        return 2
    mode = argv[1]
    if mode == 'audit':
        args = [a for a in argv[2:] if not a.startswith('--')]
        expanded = [p for pat in (args or ['/tmp/md/*', 'research/harddisk/extracted/*'])
                    for p in (glob.glob(pat) or [pat])]
        audit(expanded)
        return 0
    if mode == 'jump' and len(argv) >= 3:
        path = argv[2]
        if '--hex' in argv:
            buf, origin = load_hex(path)
            reloc = False
        else:
            buf, origin = open(path, 'rb').read(), 0
            reloc = True
        print('%s: %d bytes, origin 0x%04X, %s' % (
            os.path.basename(path), len(buf), origin,
            'relocatable (operands are offsets from the jump table)' if reloc
            else 'absolute'))
        target = jump(buf, reloc)
        if not reloc and target is not None:
            target -= origin          # an absolute target -> a file offset
        seldsk(buf, target)
        return 0
    print(__doc__.strip())
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv))
