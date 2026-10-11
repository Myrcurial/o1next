#!/usr/bin/env python3
"""Draw the o1nextgen wordmark the way the Osborne logo is drawn.

The first attempt rasterised a traced SVG outline, which stair-steps badly: the
wordmark's strokes were three character cells thick, and the graphics set only
resolves two sub-pixels per cell, so every curve came out ragged.

This starts from the real thing instead.  AUTOCPM.ASM's logo art (10/12/81, Thom
Hogan) decodes to a clean geometry, measured rather than eyeballed:

    cap height      50 sub-pixels
    stroke          15 sub-pixels   (the ring's sides)
    corner radius   ~6
    hatch           full-width rules, 2 thick, every 8 sub-pixels
    canvas          128 x 56 sub-pixels = 64 x 28 character cells

Everything is drawn to those numbers with the proportions of a heavy grotesque
(Arial Bold-ish: uniform stems, flat terminals, equal arms), then converted to the
machine's graphics characters by the table in tools/o1art.py.  Nothing is
downsampled, so the result is as clean as the medium allows.

The drawn O is checked against the recovered art -- if the geometry is right, they
should agree almost pixel for pixel.

    tools/o1logo.py OUTDIR [--name o1nextgen]
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from o1art import block_table, emit_art, emit_png, glyph_bitmaps, ROM  # noqa: E402

CAP, STROKE, RAD = 50, 15, 6      # measured from the AUTOCPM O
STROKE_H = 13                     # horizontals thinner than verticals, as a round
                                  # letter has it -- and the O's counter is taller
                                  # for it, at the same width
HATCH, HATCH_T = 8, 2             # full-width rules, every 8 sub-pixels
HATCH_MID = 25                    # the middle of the three rules the O's counter
                                  # straddles: the one that carries through a G
TOP = 4                           # the O's ink starts at sub-row 4
TRACK = 8                         # letter spacing

def canvas(w, h):
    return [[0] * w for _ in range(h)]


def fill(bm, x, y, w, h, v=1):
    for r in range(max(0, y), min(len(bm), y + h)):
        row = bm[r]
        for c in range(max(0, x), min(len(row), x + w)):
            row[c] = v


def rounded(bm, x, y, w, h, r, v=1):
    """A rounded rectangle, radius r, filled."""
    fill(bm, x + r, y, w - 2 * r, h, v)
    fill(bm, x, y + r, w, h - 2 * r, v)
    for cy in range(r):
        for cx in range(r):
            if (r - cx) ** 2 + (r - cy) ** 2 <= r * r + r:
                for px in (x + cx, x + w - 1 - cx):
                    for py in (y + cy, y + h - 1 - cy):
                        fill(bm, px, py, 1, 1, v)


def ring(bm, x, y, w, h, r, sv=STROKE, sh=None):
    """A ring whose horizontals can be thinner than its verticals."""
    sh = sv if sh is None else sh
    rounded(bm, x, y, w, h, r, 1)
    rounded(bm, x + sv, y + sh, w - 2 * sv, h - 2 * sh, max(1, r - sv // 2), 0)


def diagonal(bm, x0, y0, x1, y1, t):
    """A thick diagonal, one row at a time: clean at this scale."""
    steps = max(1, abs(y1 - y0))
    for i in range(steps + 1):
        y = y0 + (i if y1 > y0 else -i)
        x = x0 + (x1 - x0) * i // steps
        fill(bm, x - t // 2, y, t, 1, 1)


def draw(ch, bm, x, y):
    """Draw one cap, return its advance width.  Arial Bold proportions."""
    if ch == "O":
        ring(bm, x, y, 52, CAP, RAD, STROKE, STROKE_H)
        return 52
    if ch == "G":
        ring(bm, x, y, 52, CAP, RAD, STROKE, STROKE_H)
        # The opening is one hatch line and nothing else: the ring stays solid
        # above it -- cutting a taller gap notches the upper arm -- and closes
        # from the bar down to the bottom stroke.
        fill(bm, x + 30, y + HATCH_MID - TOP, 24, HATCH_T, 0)
        fill(bm, x + 26, y + 27, 26, STROKE, 1)      # the bar
        return 52
    if ch == "1":
        fill(bm, x + 6, y, STROKE, CAP)
        fill(bm, x + 2, y, 10, 12)               # the flag
        return 22
    if ch == "N":
        fill(bm, x, y, STROKE, CAP)
        fill(bm, x + 33, y, STROKE, CAP)
        diagonal(bm, x + 8, y + 1, x + 41, y + CAP - 1, 17)
        return 48
    if ch == "E":
        fill(bm, x, y, STROKE, CAP)
        fill(bm, x, y, 38, STROKE)
        fill(bm, x, y + (CAP - STROKE) // 2, 31, STROKE)
        fill(bm, x, y + CAP - STROKE, 38, STROKE)
        return 38
    if ch == "X":
        diagonal(bm, x + 8, y + 1, x + 38, y + CAP - 1, 17)
        diagonal(bm, x + 38, y + 1, x + 8, y + CAP - 1, 17)
        return 46
    if ch == "T":
        fill(bm, x, y, 44, STROKE)
        fill(bm, x + (44 - STROKE) // 2, y, STROKE, CAP)
        return 44
    raise SystemExit("no drawing for " + ch)


def compose(word):
    widths = [draw(ch, canvas(1, 1), 0, 0) for ch in word]
    total = sum(widths) + TRACK * (len(word) - 1)
    bm = canvas(total, TOP + CAP + 6)
    for y in range(1, len(bm), HATCH):           # the hatch, as in the art
        fill(bm, 0, y, total, HATCH_T)
    x = 0
    for ch, w in zip(word, widths):
        draw(ch, bm, x, TOP)                     # letters sit over the hatch
        x += w + TRACK
    return bm


def to_cells(bm, table):
    cells = []
    for cy in range(len(bm) // 2):
        line = []
        for cx in range(len(bm[0]) // 2):
            p = (bm[cy * 2][cx * 2] | (bm[cy * 2][cx * 2 + 1] << 1) |
                 (bm[cy * 2 + 1][cx * 2] << 2) | (bm[cy * 2 + 1][cx * 2 + 1] << 3))
            line.append(p)
        cells.append(line)
    return cells


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("outdir")
    ap.add_argument("--name", default="o1nextgen")
    ap.add_argument("--word", default="O1NEXTGEN")
    ap.add_argument("--scale", type=int, default=2)
    args = ap.parse_args(argv)

    glyphs = glyph_bitmaps(ROM)
    table = block_table(glyphs)
    bm = compose(args.word)
    cells = to_cells(bm, table)

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    emit_art(cells, table, args.name, out / (args.name + ".art.txt"))
    w, h = emit_png(cells, glyphs, table, out / (args.name + ".png"), args.scale)
    used = sorted({table[p] for row in cells for p in row})
    print("%s: %d x %d cells from a %dx%d drawing" %
          (args.name, len(cells[0]), len(cells), len(bm[0]), len(bm)))
    print("  glyphs: %s" % ", ".join("%d(%s)" % (g, chr(g + 65)) for g in used))
    print("  wrote %s.art.txt and %s.png (%dx%d)" % (args.name, args.name, w, h))
    return 0


if __name__ == "__main__":
    sys.exit(main())
