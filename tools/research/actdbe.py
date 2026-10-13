#!/usr/bin/env python3
"""actdbe.py -- rewrite SORCIM ACT `DBE`/`DCE` lines as ordinary `DB` lines.

WHY THIS EXISTS
    The Osborne ROM 1.3 source (`research/source-code/ROM-13-source/`) uses two
    pseudo-ops that only ACT **3.5E** has: `DBE` and `DCE`.  Every `ACT80.COM`
    the local archive holds is 3.0 or 3.2 -- the SORCIM kit, both MORROW copies,
    five LOOSECPM issues, and the schorn.ch `act.dsk` (3.2 plus ACT II 8086
    3.4) -- and none of them carries `DBE`/`DCE` anywhere in its mnemonic table.
    The rev-B listing on `OCCROM.IMD` names the version it was built with:
    `SORCIM 808x Assembler ver  3.5E`.  So the source needs an assembler we do
    not have, and this tool is the honest half-measure: it rewrites the two
    pseudo-ops into `DB` so that 3.0 can assemble the same bytes.

    What they do is recoverable *exactly*, because the rev-B ROM source on
    `OCCROM.IMD` uses them and that same disk carries the shipped image
    (`OCCROM0B.COM`, 4096 B) and its full listing.  Comparing the listing's
    DBE/DCE lines against the bytes in the shipped ROM gives one rule, holding
    over all fifteen lines:

        byte = value * 2          (DBE -- every byte even)
        byte = value * 2 + 1      (DCE -- the *last* byte only)

    i.e. the strings are stored shifted left one bit, and `DCE` sets bit 0 of
    the final byte as an end-of-string marker.  That is the format OSTR reads:
    `rom144.asm` documents "OSTR RECOGNIZES 7F AS AN ESCAPE SEQUENCE TO REPEAT
    CHAR N TIMES".  The rev-B ROM holds 18 literal 0x7F bytes, but none of them
    falls inside a DBE/DCE string, so no escape handling is needed here.

    This rewrites each `DBE`/`DCE` statement into `DB` statements whose operands
    are the same expressions multiplied by two, leaving ACT to evaluate the
    symbols (`cr`, `lf`) exactly as it would have.  The original statement is
    kept as a trailing comment so the result stays auditable, and the transform
    is *verified* by rebuilding rev B and comparing against `OCCROM0B.COM` --
    `rom13-reassemble.sh --validate`.

TWO THINGS THE FIRST CUT GOT WRONG
    Both were silent, and both are worth keeping:

    * **The CP/M source is CRLF.**  Emitting the new lines with bare LF makes
      ACT read them joined to the following line, and the *source text* then
      lands in the hex file as object code.  The rewrite preserves the input's
      line ending.
    * **`!` is ACT's statement separator**, and
      `DBE cr,lf,'Program begins' ! DCE ':'` is one line with two statements.
      Each statement is rewritten separately.  ACT's local labels are also
      `:name:` with a leading colon, which a label regex that only allows
      `name:` will silently miss -- and those two lines then stay as `DBE` and
      error out.

USAGE
    actdbe.py IN.asm [OUT.asm]      (no OUT = read stdin, write stdout)

Issue: #205 (see docs/rom-13-reconstruction.md).
"""
import re
import sys

MAXOPS = 6          # operands per emitted DB line, to keep lines short
STMT = re.compile(r'^(\s*)'
                  r'((?::[A-Za-z0-9_.$]+:)|(?:[A-Za-z0-9_.$]+:))?'
                  r'\s*(DBE|DCE)\s+(.*?)\s*$')


def split_args(s):
    """Split an ACT operand list on top-level commas (quotes respected)."""
    out, cur, q = [], '', False
    for ch in s:
        if ch == "'":
            q = not q
            cur += ch
        elif ch == ',' and not q:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def split_stmts(line):
    """Split a source line on ACT's `!` statement separator."""
    out, cur, q = [], '', False
    for ch in line:
        if ch == "'":
            q = not q
            cur += ch
        elif ch == '!' and not q:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    out.append(cur)
    return out


def expand(label, op, args):
    """The `DB` lines for one DBE/DCE statement, or None if it has no operands."""
    ops = []
    for a in split_args(args):
        if len(a) >= 3 and a.startswith("'") and a.endswith("'"):
            ops += [f"'{ch}'" for ch in a[1:-1]]      # string literal
        else:
            ops.append(f"({a})")                      # expression: cr, 'Z'-40h
    if not ops:
        return None
    ops = [f'{o}*2' for o in ops]
    if op.upper() == 'DCE':
        ops[-1] += '+1'
    lines = []
    for i in range(0, len(ops), MAXOPS):
        # `label` is None when the statement had none -- `or ''` matters, or the
        # literal text "None" is emitted as a label and ACT errors on it.
        lab = (label or '') if i == 0 else ''
        tail = f'\t; {op}\t{args}' if i == 0 else ''
        lines.append(f'{lab}\tDB\t' + ','.join(ops[i:i + MAXOPS]) + tail)
    return lines


def rewrite(text):
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = [l[:-1] if l.endswith('\r') else l for l in text.split('\n')]
    out = []
    for line in lines:
        stmts = split_stmts(line)
        if not any(STMT.match(s) for s in stmts):
            out.append(line)
            continue
        for s in stmts:
            m = STMT.match(s)
            if m:
                indent, label, op, args = m.groups()
                out += [indent + e for e in expand(label, op, args)]
            elif s.strip():
                out.append(s.rstrip())
    return nl.join(out) + nl


def main():
    src = (open(sys.argv[1], 'rb').read().decode('latin-1')
           if len(sys.argv) > 1 else sys.stdin.read())
    dst = rewrite(src)
    if len(sys.argv) > 2:
        open(sys.argv[2], 'wb').write(dst.encode('latin-1'))
    else:
        sys.stdout.write(dst)


if __name__ == '__main__':
    main()
