#!/usr/bin/env python3
"""rom2strokes.py -- read the authored boot-screen art as geometry, and cost it.

WHY THIS EXISTS
    ROM 2.00's boot screen is hand-drawn (`research/boot-screen/`) and has to be
    produced by the machine.  `docs/o1-rom-2.0.md` section 2.3 leaves **511 bytes
    of the ROM window spare**, so the question is whether the art can be described
    in that budget -- and the answer is not obvious either way, which is why it is
    measured here rather than guessed.

WHAT IT FOUND (2026-10-14, #83)
    **The stripes are free.**  The art is 14 content rows interleaved with 14
    blank ones, so a stem spanning nine content rows is one continuous stem that
    the machine draws on alternate rows.  Lift the art to the 2x2 sub-pixel grid,
    fill the stripes back in, cover the letterform with rectangles, then draw the
    rectangles back through the mask and compare: it is **exact**, 0 sub-pixels
    wrong on every letter.  A rectangle may be stored once and masked at draw
    time instead of being sliced into 1-row pieces.

    **But it still does not fit.**  Every raster-shaped encoding of the logo lands
    in the same band:

        raw bitmap, striped, 1 bit per sub-pixel      857 B
        RLE bytecode (the scheme the design assumes)  816 B
        the exact rectangle cover                     784 B

    The letters are heavy -- roughly 40% of a letterform is ink -- so there is
    little redundancy to exploit, and the cover is dominated by the diagonals: the
    X alone is 72 rectangles (288 B) where it is structurally two strokes.

    **A segment model would be smaller, and was not converged.**  A greedy fit
    over the two diagonal families the art uses recovers 56-76% of the ink, and a
    four-angle fit does worse.  So the stroke route is *estimated*, not
    demonstrated -- the X is 2 strokes against 288 B and the T is 2 against 36 B,
    but nothing here proves a fitter can find them.

    **And it does not need to fit.**  One window page is 4096 bytes and the video
    buffer is 128 x 32 = 4096 cells, so **one page is exactly one screen**; in
    bank 2 the window and the video RAM are both visible (`docs/o1-rom-2.0.md`
    section 4.4), so a frame is one `LDIR` from `1000h` to `F000h`, and the frames
    live in the interposer's flash rather than the ROM.  `--frame` writes one.

Usage:
    tools/research/rom2strokes.py                  # the stripe proof and the costs
    tools/research/rom2strokes.py --frame OUT.bin  # one 4096-byte video buffer
"""
import argparse
import importlib.util
import os
import sys
import zlib

# --- the art's alphabet ---------------------------------------------------
#
# 0x41-0x61 is graphics: glyph = charcode - 65, the `sui 65` the ROM's loader
# does.  Everything else printable is text, and the glyph is the code.

GRAPHICS_FIRST, GRAPHICS_LAST = 0x41, 0x61
ART_OFFSET = 65
BLANK = 32

# --- the video buffer -----------------------------------------------------

STRIDE, ROWS = 128, 32
FRAME = STRIDE * ROWS                     # 4096: one buffer, and one window page

# The letter boxes, measured off `o1next-art.txt` (research/boot-screen/README).
BOXES = [('O', 26, 46), ('1', 47, 59), ('N', 61, 82),
         ('E', 84, 102), ('X', 104, 127), ('T', 129, 152)]


def _sibling(name):
    here = os.path.dirname(os.path.abspath(__file__))
    for d in (here, os.path.dirname(here)):
        path = os.path.join(d, name)
        if os.path.exists(path):
            break
    else:
        raise SystemExit("rom2strokes.py: cannot find %s beside this tool" % name)
    spec = importlib.util.spec_from_file_location(name[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_art(path):
    lines = [l for l in open(path, encoding='latin-1').read().split('\n') if l]
    w = max(len(l) for l in lines)
    return [l.ljust(w) for l in lines]


def glyphs():
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    return _sibling('o1art.py').glyph_bitmaps(
        os.path.join(repo, 'tools', 'emulator-setup', 'roms', 'char.ua15'))


def quadrant(bm):
    """The 2x2 sub-pixel pattern a glyph draws, from the glyph's own pixels."""
    if bm is None:
        return 0
    q = [sum(bm[r][c] for r in range(0, 5) for c in range(0, 4)),
         sum(bm[r][c] for r in range(0, 5) for c in range(4, 8)),
         sum(bm[r][c] for r in range(5, 10) for c in range(0, 4)),
         sum(bm[r][c] for r in range(5, 10) for c in range(4, 8))]
    return (1 if q[0] >= 9 else 0) | (2 if q[1] >= 9 else 0) \
        | (4 if q[2] >= 9 else 0) | (8 if q[3] >= 9 else 0)


def subgrid(rows, x0, x1, pat):
    """A letter as a 2x sub-pixel bitmap: 2R rows by 2W columns."""
    bm = [[0] * (2 * (x1 - x0 + 1)) for _ in range(2 * len(rows))]
    for r, line in enumerate(rows):
        for c in range(x0, x1 + 1):
            p = pat.get(ord(line[c]) - ART_OFFSET, 0)
            for dy in range(2):
                for dx in range(2):
                    if p >> (dy * 2 + dx) & 1:
                        bm[2 * r + dy][2 * (c - x0) + dx] = 1
    return bm


def unstripe(bm):
    """Fill the blank cell rows back in, where the ink continues above and below.

    The mask is alternate *cell* rows, two sub-rows each, so this looks two
    sub-rows up and two down: if both are inked in this column, the gap was a
    stripe and the letterform runs through it.
    """
    out = [row[:] for row in bm]
    for r in range(2, len(bm) - 2):
        if any(bm[r]):
            continue
        for c in range(len(bm[0])):
            if bm[r - 2][c] and bm[r + 2][c]:
                out[r][c] = 1
    return out


def stripe(bm):
    """The mask the machine applies: blank the odd cell rows."""
    return [[v if (r // 2) % 2 == 0 else 0 for v in row]
            for r, row in enumerate(bm)]


def cover(bm):
    """Cover the bitmap with rectangles, merging identical runs downwards."""
    rects, active = [], {}
    for r, row in enumerate(bm):
        runs, c = [], 0
        while c < len(row):
            if row[c]:
                s = c
                while c < len(row) and row[c]:
                    c += 1
                runs.append((s, c - 1))
            else:
                c += 1
        new = {}
        for run in runs:
            new[run] = (active[run][0], r) if run in active else (r, r)
        for run, span in active.items():
            if run not in new:
                rects.append((run[0], run[1], span[0], span[1]))
        active = new
    for run, span in active.items():
        rects.append((run[0], run[1], span[0], span[1]))
    return rects


def draw(rects, r_max, c_max):
    bm = [[0] * c_max for _ in range(r_max)]
    for x0, x1, r0, r1 in rects:
        for r in range(r0, r1 + 1):
            for c in range(x0, x1 + 1):
                bm[r][c] = 1
    return bm


def to_art(bm, pat):
    """Back to the art's alphabet, one character per cell."""
    inv = {p: g for g, p in pat.items()}
    out = []
    for r in range(0, len(bm), 2):
        row = []
        for c in range(0, len(bm[0]), 2):
            p = bm[r][c] | (bm[r][c + 1] << 1) | (bm[r + 1][c] << 2) \
                | (bm[r + 1][c + 1] << 3)
            row.append(chr(inv.get(p, BLANK) + ART_OFFSET))
        out.append(''.join(row))
    return out


def rle_bytes(rows):
    """The bytecode the design assumes: glyph, 7F n c, skip, row-repeat, newline."""
    tot, prev = 0, None
    for r in rows:
        if prev is not None and r == prev:
            tot += 2
            continue
        tot += 1
        i = 0
        while i < len(r):
            c, j = r[i], i
            while j < len(r) and r[j] == c:
                j += 1
            n = j - i
            tot += n if n < 4 else 3
            i = j
        prev = r
    return tot

    return _sibling('o1art.py').glyph_bitmaps(
        os.path.join(repo, 'emulator-setup', 'roms', 'char.ua15'))


def report(rows, pat):
    print('the letterforms, as geometry')
    print('=' * 72)
    print('%-2s %5s %6s %7s %7s %8s' %
          ('', 'cells', 'ink', 'raw B', 'RLE B', 'rects B'))
    tot = [0] * 5
    for name, x0, x1 in BOXES:
        art = subgrid(rows, x0, x1, pat)
        cont = unstripe(art)
        rects = cover(cont)
        back = stripe(draw(rects, len(cont), len(cont[0])))
        wrong = sum(1 for r in range(len(art)) for c in range(len(art[0]))
                    if art[r][c] != back[r][c])
        sub_rows = len(art) // 2          # the stripes halve what must be stored
        raw = (2 * (x1 - x0 + 1) * sub_rows + 7) // 8
        ink = sum(map(sum, art))
        rle = rle_bytes(to_art(art, pat))
        rect = len(rects) * 4
        for i, v in enumerate((x1 - x0 + 1, ink, raw, rle, rect)):
            tot[i] += v
        print('%-2s %5d %6d %7d %7d %8d%s'
              % (name, x1 - x0 + 1, ink, raw, rle, rect,
                 '   exact' if wrong == 0 else '   %d WRONG' % wrong))
    print('-' * 72)
    print('%-2s %5d %6d %7d %7d %8d' % ('', *tot))
    print()
    print('The ROM window spare is 511 B (docs/o1-rom-2.0.md section 2.3).  Every')
    print('raster-shaped encoding lands in the same band and none of them fits:')
    print('the letters are heavy, so there is little redundancy to exploit, and the')
    print('cover is dominated by diagonals -- the X is 72 rectangles where it is')
    print('structurally two strokes.')
    print()
    print('A *segment* model would be far smaller (the X is 2 strokes against')
    print('288 B, the T is 2 against 36 B) but no fitter here converged on one, so')
    print('that route is estimated, not demonstrated.')


def frame(rows, origin):
    """One video buffer: the art placed so that `origin` lands at column 0.

    The buffer holds **glyph codes**, not art characters, so the `sui 65` split
    is applied here, at build time -- the ROM never has to branch.  0x41-0x61 is
    graphics (code = char - 65); anything else printable is the code itself.

    `origin` is not cosmetic.  The art is 153 columns and a screen is 128, so 25
    columns have to go -- and there are only two candidates: the 26 columns of
    hatch to the left of the O, or the T.  Placing the *logo* at column 0 keeps
    the logo whole and drops the hatch, which is the right trade: the hatch is a
    rule loop and can be drawn back at run time, and the O sliding off the left
    edge still reads as the logo stretching, hatch or no hatch.
    """
    buf = [BLANK] * FRAME
    for r, line in enumerate(rows):
        if r >= ROWS:
            break
        for c in range(len(line)):
            col = c - origin
            if not 0 <= col < STRIDE:
                continue
            o = ord(line[c])
            if GRAPHICS_FIRST <= o <= GRAPHICS_LAST:
                buf[r * STRIDE + col] = o - ART_OFFSET
            elif 0x20 <= o <= 0x7E:
                buf[r * STRIDE + col] = o
    return bytes(buf)


def main(argv=None):
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap = argparse.ArgumentParser(
        description='Read the boot-screen art as geometry, and cost it.')
    ap.add_argument('--art', default=os.path.join(
        repo, 'research', 'boot-screen', 'o1next-art.txt'))
    ap.add_argument('--frame', metavar='OUT.bin',
                    help='also write one 4096-byte video buffer')
    ap.add_argument('--origin', type=int, default=26,
                    help='art column to place at buffer column 0 (default 26, '
                         'the O\'s left edge: the logo fits, the hatch does not)')
    args = ap.parse_args(argv)

    rows = load_art(args.art)
    pat = {g: quadrant(b) for g, b in glyphs().items()}
    pat[BLANK] = 0
    report(rows, pat)

    if args.frame:
        buf = frame(rows, args.origin)
        with open(args.frame, 'wb') as fh:
            fh.write(buf)
        print()
        print('wrote %s: %d bytes = %d x %d cells = one window page (4096)'
              % (args.frame, len(buf), STRIDE, ROWS))
        print('CRC32 %08x' % (zlib.crc32(buf) & 0xFFFFFFFF))
        print()
        print("So the boot screen is one `LDIR` from 1000h to F000h per frame,")
        print("with the frames in the interposer's flash -- about 40 bytes of")
        print('ROM, not 511.  And the animation is the viewport slide: a register')
        print('write, and nothing else.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

