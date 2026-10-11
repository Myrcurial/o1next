#!/usr/bin/env python3
"""Render an image as Osborne 1 graphics characters — the AUTOCPM technique.

Why this exists
---------------
The original Osborne boot logo (`AUTOCPM.ASM`, 10/12/81, Thom Hogan) is a picture
drawn in the machine's own graphics characters: 0x00-0x1F, a set of half-blocks,
quarters and diagonals that gives **four bits of picture per character cell** (a
2x2 sub-grid).  The loader turns it on with `sui 65` — subtract 65 from every byte
so that ASCII letters index the glyphs, which is why the source is a page of Ys.

That is a general technique, so this is a general tool: give it an image and a
width in characters, and it picks, for every cell, the ROM glyph that best matches
that cell's 2x2 sub-pattern.  The glyph is chosen by pixel error against the ideal
pattern, from the ROM itself, so the diagonals are used where they help.

Two artifacts come out:

  NAME.art.txt   the art as ASCII, assembler-ready (`db '...'` lines, the same
                 form as AUTOCPM) — this is the *source*, and it is what the
                 o1ng could print at boot
  NAME.png       the same art rendered with the ROM's own glyph bitmaps, for the
                 web, pixel-exact because a pixel-art logo should not be scaled

The ROM is the only authority for the glyph shapes, so nothing here is drawn by
hand.

Usage
-----
    tools/o1art.py IMAGE OUTDIR [--name NAME] [--cells N]

IMAGE may be any format `sips` can read (macOS built-in); SVG is converted via
`qlmanage` first.  The ink is cropped to its bounding box, so padding and
surrounding white space do not matter.  --cells sets the width in characters
(default: 64, the width of the AUTOCPM logo).
"""
import argparse
import re
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROM = REPO / "tools" / "emulator-setup" / "roms" / "char.ua15"
CELL_W, CELL_H = 8, 10
BLANK = 32                      # glyph 32 is a space: the "no ink" cell

def glyph_bitmaps(rom_path):
    """The 32 graphics glyphs as 8x10 bitmaps, straight out of the ROM."""
    data = Path(rom_path).read_bytes()
    return {g: [[(data[r * 128 + g] >> (7 - c)) & 1 for c in range(CELL_W)]
                for r in range(CELL_H)] for g in range(32)}


def block_table(glyphs):
    """For each 2x2 sub-pattern, the glyph that draws it with least error.

    The ideal cell for a pattern is each quadrant solid or empty; the ROM glyph
    whose pixels differ least from that ideal wins.  Pattern 0 is always blank.
    """
    table = {}
    for pattern in range(16):
        if pattern == 0:
            table[pattern] = BLANK
            continue
        ideal = [[0] * CELL_W for _ in range(CELL_H)]
        for r in range(CELL_H):
            for c in range(CELL_W):
                q = (r >= CELL_H // 2) * 2 + (c >= CELL_W // 2)
                ideal[r][c] = (pattern >> q) & 1
        best, best_err = None, 1 << 30
        for g, bm in glyphs.items():
            err = sum(bm[r][c] != ideal[r][c]
                      for r in range(CELL_H) for c in range(CELL_W))
            if err < best_err:
                best, best_err = g, err
        table[pattern] = best
    return table


def read_image(path):
    """Return (width, height, rows) of 0/1 ink, via sips/qlmanage -> BMP."""
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(path)
        if src.suffix.lower() == ".svg":
            subprocess.run(["qlmanage", "-t", "-s", "2048", "-o", tmp, str(src)],
                           check=True, capture_output=True)
            src = Path(tmp) / (src.name + ".png")
        bmp = Path(tmp) / "in.bmp"
        subprocess.run(["sips", "-s", "format", "bmp", str(src), "--out", str(bmp)],
                       check=True, capture_output=True)
        data = bmp.read_bytes()

    pixoff = struct.unpack_from("<I", data, 10)[0]
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    topdown, height = height < 0, abs(height)
    stride, step = ((width * bpp // 8) + 3) & ~3, bpp // 8
    rows = []
    for y in range(height):
        base = pixoff + (y if topdown else height - 1 - y) * stride
        row = []
        for x in range(width):
            o = base + x * step
            lum = (data[o + 2] * 299 + data[o + 1] * 587 + data[o]) // 1000
            row.append(1 if lum < 128 else 0)
        rows.append(row)
    return width, height, rows


def crop_ink(width, height, rows):
    """Trim to the bounding box of the ink, so padding does not matter."""
    xs = [x for y in range(height) for x in range(width) if rows[y][x]]
    ys = [y for y in range(height) if any(rows[y])]
    if not xs:
        raise SystemExit("the image has no ink at all")
    x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
    return x1 - x0, y1 - y0, [r[x0:x1] for r in rows[y0:y1]]


def to_cells(width, height, rows, cells_wide):
    """Sample the image to a 2x2 sub-grid per character cell and pick glyphs."""
    sub_w, sub_h = cells_wide * 2, max(1, round(cells_wide * 2 * height / width))
    grid = []
    for sy in range(sub_h):
        line = []
        for sx in range(sub_w):
            x = min(width - 1, (sx * width) // sub_w)
            y = min(height - 1, (sy * height) // sub_h)
            line.append(rows[y][x])
        grid.append(line)
    # each cell's 2x2 pattern, quadrant order: bit0 top-left, 1 top-right,
    # 2 bottom-left, 3 bottom-right
    cells = []
    for cy in range(sub_h // 2):
        line = []
        for cx in range(sub_w // 2):
            p = (grid[cy * 2][cx * 2] | (grid[cy * 2][cx * 2 + 1] << 1) |
                 (grid[cy * 2 + 1][cx * 2] << 2) | (grid[cy * 2 + 1][cx * 2 + 1] << 3))
            line.append(p)
        cells.append(line)
    return cells

def write_png(path, width, height, pixels):
    """pixels: rows of (r,g,b,a)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for px in row:
            raw.extend(px)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)) +
           chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    Path(path).write_bytes(png)


def emit_art(cells, table, name, out):
    """The art as ASCII: `sui 65` turns it back into glyph indices."""
    lines, buf = [], ""
    for row in cells:
        for pattern in row:
            ch = chr(table[pattern] + 65)
            buf += "\\\\" if ch == "\\" else ch
        lines.append(buf)
        buf = ""
    body = "\n".join("\tdb\t'%s'" % l for l in lines)
    text = ("; %s.art -- Osborne 1 graphics art, %d x %d characters.\n"
            "; Generated by tools/o1art.py from the ROM's own glyphs.\n"
            "; Load exactly as AUTOCPM does: sui 65 over %d bytes.\n"
            "%s:\n%s\n\tdb\t'$'\n"
            % (name, len(cells[0]), len(cells), len(cells) * len(cells[0]),
               name, body))
    Path(out).write_text(text)
    return len(lines[0]) * len(lines)


def emit_png(cells, glyphs, table, out, scale=2, ink=(255, 255, 255)):
    w, h = len(cells[0]) * CELL_W * scale, len(cells) * CELL_H * scale
    clear = (0, 0, 0, 0)
    grid = [[clear] * w for _ in range(h)]
    for cy, row in enumerate(cells):
        for cx, pattern in enumerate(row):
            g = table[pattern]
            if g == BLANK:
                continue
            bm = glyphs[g] if g < 32 else [[0] * CELL_W for _ in range(CELL_H)]
            for r in range(CELL_H):
                for c in range(CELL_W):
                    if bm[r][c]:
                        for dy in range(scale):
                            for dx in range(scale):
                                grid[cy * CELL_H * scale + r * scale + dy][
                                    cx * CELL_W * scale + c * scale + dx] = \
                                    ink + (255,)
    write_png(out, w, h, grid)
    return w, h


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("image")
    ap.add_argument("outdir")
    ap.add_argument("--name", default="logo")
    ap.add_argument("--cells", type=int, default=64,
                    help="width in characters (AUTOCPM used 64)")
    ap.add_argument("--scale", type=int, default=2, help="PNG pixels per ROM pixel")
    args = ap.parse_args(argv)

    glyphs = glyph_bitmaps(ROM)
    table = block_table(glyphs)
    w, h, rows = crop_ink(*read_image(args.image))
    cells = to_cells(w, h, rows, args.cells)

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    n = emit_art(cells, table, args.name, out / (args.name + ".art.txt"))
    pw, ph = emit_png(cells, glyphs, table, out / (args.name + ".png"),
                      args.scale)
    used = sorted({table[p] for row in cells for p in row})
    print("%s: %d x %d cells from a %dx%d crop" %
          (args.name, len(cells[0]), len(cells), w, h))
    print("  glyphs used: %s" % ", ".join(
        "%d(%s)" % (g, chr(g + 65)) for g in used))
    print("  wrote %s.art.txt (%d bytes of art) and %s.png (%dx%d)" %
          (args.name, n, args.name, pw, ph))
    return 0


if __name__ == "__main__":
    sys.exit(main())
