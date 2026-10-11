#!/usr/bin/env python3
"""Turn the Osborne 1 character generator ROM into a real web font (#44).

Why this exists
---------------
The 2716 in socket UA15 is the machine's own typeface: 128 characters of 8x10
pixels.  The blog is set in it, so the page is written in the same letters the
Osborne 1 would have drawn on its own screen.

The storage layout is *not* the obvious one.  It is row-major **across**
characters, not glyph-contiguous:

    byte = rom[row * 128 + charcode]        # bit 7 = leftmost pixel

so all 128 characters' row 0 are contiguous, then all of row 1, and so on --
10 rows x 128 characters = 1280 bytes, with the rest of the 2 KiB left as 0xFF.
That comes from MAME's ``osborne1`` driver, which is the authority this project
already cites for the ROM set:

    u8 const gfx = m_p_chargen[(ra << 7) | (chr & 0x7f)];
    p = std::fill_n(p, Scale, BIT(gfx, 7 - b) ? clr : 0);

Guessing this cost half an hour; the driver had it in one line.

What it emits
-------------
A family, one file per display width the machine has, each as ``.ttf`` and
``.woff2``:

- ``osborne1-52.*``  -- the machine's own cell, 8x10 pixels, at full dot width
- ``osborne1-80.*``  -- the same glyphs at 65% dot width (52/80)
- ``osborne1-104.*`` -- the same glyphs at 50% dot width (52/104)

**The physical screen width does not change between modes -- the type gets
narrower.** So the three faces share height, pixel components and vertical
metrics, and differ only in horizontal scale: 104 columns fit in the space 52
occupied. Because the cell is 8 pixels wide and ``SCALE`` is 100 font units per
pixel, the horizontal dot width is exactly ``100 * 52 / columns`` -- a whole
number for all three (100, 65, 50), so nothing rounds.

Each glyph is built from one rectangle per horizontal run of set pixels, so the
outlines are exact rather than traced.

What it deliberately does *not* emit (yet)
-------------------------------------------
The 0x00-0x1F graphics set is not in the shipped font.  It is Osborne's own
encoding, not Unicode, so each glyph has to be *identified* rather than assumed
-- see #97, and `--glyph-sheet` below, which exists to make that identification
checkable.

One thing is already clear from looking at them, and it changes what the
candidates are: the set is **block graphics**, not the Unicode box-drawing line
set.  It is quadrants, halves, staircases, triangles, a circle, a cross and a
hatch -- which is why the manual's own section is titled "5.5 BLOCK GRAPHICS"
(*Osborne 1 Technical Manual* p. 25).  So the things to compare against are
Block Elements (U+2580-259F) and Geometric Shapes, not U+2500-257F.

Verification
------------
The tool reloads the font it just built, rasterises every glyph back to 8x10
bits and compares them against the ROM.  If that fails it writes nothing.  Pass
``--specimen FILE.png`` to also render a specimen sheet, which is how a human
checks it.

Requires fonttools + brotli (``pip3 install fonttools brotli``) -- build-time
only; the artifacts are committed.

Usage
-----
    tools/romfont.py                       # write the font family
    tools/romfont.py --check               # fail if they are stale (CI)
    tools/romfont.py --specimen /tmp/f.png # also render a specimen sheet
    tools/romfont.py --glyph-sheet /tmp/g.png   # the graphics set, for #97
"""
import argparse
import struct
import sys
import zlib
from pathlib import Path

from fontTools.agl import UV2AGL
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

REPO = Path(__file__).resolve().parent.parent
DEFAULT_ROM = REPO / "tools" / "emulator-setup" / "roms" / "char.ua15"
OUT_DIR = REPO / "site" / "assets" / "fonts"

COLS, ROWS = 8, 10      # the character cell, in pixels
STRIDE = 128            # bytes per row across all characters
FIRST, LAST = 0x20, 0x7E
SCALE = 100             # font units per pixel, vertically
UPEM = ROWS * SCALE     # 1000: one cell is exactly one em, so line-height 1.0

# The display widths the machine has, and the one the family is measured from.
COLUMNS = (52, 80, 104)
BASE_COLUMNS = 52


def xscale(columns):
    """Font units per pixel *horizontally*, for a given display width.

    The screen is a fixed width and the type narrows, so a wider mode means a
    proportionally thinner dot: 52 columns is the machine's own cell, and the
    others scale by 52/columns.  With SCALE=100 that is exactly 100, 65 and 50.
    """
    per_pixel = SCALE * BASE_COLUMNS / columns
    if per_pixel != int(per_pixel):
        raise SystemExit("column count %d does not divide SCALE * %d evenly"
                         % (columns, BASE_COLUMNS))
    return int(per_pixel)


def family(columns):
    """The font family name for one display width."""
    return "Osborne 1 %d" % columns

def decode_rom(data):
    """Return {charcode: [row bytes]} for the row-major-across-chars layout."""
    if len(data) < STRIDE * ROWS:
        raise SystemExit("ROM is %d bytes; need at least %d" %
                         (len(data), STRIDE * ROWS))
    return {ch: [data[r * STRIDE + ch] for r in range(ROWS)] for ch in range(128)}


def runs(byte):
    """Pixel runs of set bits in a row byte, as (start, end) column pairs."""
    out, start = [], None
    for c in range(COLS):
        on = (byte >> (7 - c)) & 1
        if on and start is None:
            start = c
        elif not on and start is not None:
            out.append((start, c))
            start = None
    if start is not None:
        out.append((start, COLS))
    return out


def glyph_from_rows(rows, x):
    """One rectangle per run of set pixels.

    Pixel (col, row) covers x = col*x..(col+1)*x and
    y = (ROWS-1-row)*SCALE..(ROWS-row)*SCALE: row 0 is the top of the cell and
    the baseline sits one pixel above its bottom, which is where the ROM puts
    descenders.  ``x`` is the horizontal dot width -- SCALE for the 52-column
    face, less for the compressed modes.
    """
    pen = TTGlyphPen(None)
    for r, byte in enumerate(rows):
        y0, y1 = (ROWS - 1 - r) * SCALE, (ROWS - r) * SCALE
        for x0, x1 in runs(byte):
            pen.moveTo((x0 * x, y0))
            pen.lineTo((x1 * x, y0))
            pen.lineTo((x1 * x, y1))
            pen.lineTo((x0 * x, y1))
            pen.closePath()
    return pen.glyph()


def notdef_rows():
    """A hollow box, so a missing glyph is visible rather than blank."""
    return [0xFF] + [0x81] * (ROWS - 2) + [0xFF]


def build_font(rom_data, rom_name, crc, columns=BASE_COLUMNS):
    """Build the TTFont for one display width.

    Returns (font, {charcode: row bytes}, horizontal dot width).
    """
    x = xscale(columns)
    bitmaps = decode_rom(rom_data)

    names, cmap = {}, {}
    for ch in range(FIRST, LAST + 1):
        name = UV2AGL.get(ch) or "uni%04X" % ch
        names[ch] = name
        cmap[ch] = name

    # Kramdown's smart quotes and the posts' em dashes are not in the 2716: it
    # is an ASCII font.  Point those codepoints at the glyphs the machine would
    # actually have drawn, rather than letting the browser substitute a
    # different face mid-sentence (which is what happens if they are left out --
    # it renders an acute accent in the middle of "I'm").
    EXTRA = {0x00A0: 0x20, 0x2013: 0x2D, 0x2014: 0x2D, 0x2018: 0x27,
             0x2019: 0x27, 0x201C: 0x22, 0x201D: 0x22, 0x2026: 0x2E}
    for cp, ascii_cp in sorted(EXTRA.items()):
        cmap[cp] = names[ascii_cp]

    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder([".notdef"] + [names[c] for c in sorted(names)])
    fb.setupCharacterMap(cmap)

    glyf = {".notdef": glyph_from_rows(notdef_rows(), x)}
    metrics = {".notdef": (COLS * x, 0)}
    for ch, name in names.items():
        glyf[name] = glyph_from_rows(bitmaps[ch], x)
        metrics[name] = (COLS * x, 0)
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=(ROWS - 1) * SCALE, descent=-SCALE)

    # A fixed timestamp keeps the build reproducible, so --check can compare
    # bytes.  fontTools writes seconds since 1904-01-01 here.
    import calendar
    fixed = 2082844800 + calendar.timegm((2026, 10, 8, 0, 0, 0, 0, 0, 0))
    fb.setupHead(unitsPerEm=UPEM, created=fixed, modified=fixed)

    fam = family(columns)
    fb.setupNameTable({
        "familyName": fam,
        "styleName": "Regular",
        "uniqueFontIdentifier": "%s; %s %s" % (fam, rom_name, crc),
        "fullName": fam,
        "psName": "Osborne1-%d-Regular" % columns,
        "version": "Version 1.000",
        "description": ("The Osborne 1 character generator (UA15, 2716): 128 "
                        "characters of 8x10 pixels. Decoded from %s "
                        "(CRC32 %s). ASCII 0x20-0x7E only; the 0x00-0x1F "
                        "graphics set is Osborne's own encoding, not Unicode. "
                        "This is the %d-column face: the machine's cell at "
                        "%d%% horizontal dot width, because the screen width "
                        "is fixed and only the type narrows."
                        % (rom_name, crc, columns,
                           round(100 * x / SCALE))),
    })
    fb.setupOS2(sTypoAscender=(ROWS - 1) * SCALE, sTypoDescender=-SCALE,
                sTypoLineGap=0, usWinAscent=(ROWS - 1) * SCALE,
                usWinDescent=SCALE, sxHeight=5 * SCALE, sCapHeight=7 * SCALE,
                achVendID="o1ng")
    fb.setupPost()
    return fb.font, bitmaps, x


def rasterise_glyph(glyph, x):
    """Rebuild the 10 row bitmaps from a glyph's rectangles.

    ``x`` is the horizontal dot width the glyph was built at, so the same code
    verifies every member of the family: a compressed face must still decode
    back to the identical 8x10 bits, which is the whole point.
    """
    rows = [0] * ROWS
    coords = glyph.coordinates
    if coords is None:
        return None                      # composite glyph: not ours
    start = 0
    for end in glyph.endPtsOfContours:
        pts = coords[start:end + 1]
        start = end + 1
        xs = [int(p[0]) for p in pts]
        ys = [int(p[1]) for p in pts]
        r = ROWS - 1 - (min(ys) // SCALE)
        if not 0 <= r < ROWS:
            return None
        for c in range(min(xs) // x, max(xs) // x):
            rows[r] |= 1 << (7 - c)
    return rows


def verify(font, bitmaps, x):
    """Round-trip every glyph and compare with the ROM.  Returns problems."""
    glyf = font["glyf"]
    problems = []
    for ch in range(FIRST, LAST + 1):
        name = UV2AGL.get(ch) or "uni%04X" % ch
        got = rasterise_glyph(glyf[name], x)
        if got != bitmaps[ch]:
            problems.append("U+%04X (%s): outlines do not match the ROM" %
                            (ch, name))
    return problems


# --------------------------------------------------------------------------
# specimen sheet: the human check
# --------------------------------------------------------------------------

def write_png(path, width, height, rows):
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for px in row:
            raw.extend(px)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n" +
           chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) +
           chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(png)


SPECIMEN_LINES = [
    "o1nextgen",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    "0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~",
    "Drive C + OZROM 1E: refused, no IEEE-488 driver.",
    "1234567890" * 10 + "1234",
]


def write_specimen(path, bitmaps, scale=3, pad=6):
    """Render sample text from the round-tripped glyphs."""
    lines = [[ord(c) for c in line] for line in SPECIMEN_LINES]
    width = (max(len(l) for l in lines) * COLS + 2) * scale
    height = (len(lines) * (ROWS + 2) + 2) * scale
    grid = [[(255, 255, 255)] * width for _ in range(height)]

    def put(x, y, colour):
        if 0 <= x < width and 0 <= y < height:
            grid[y][x] = colour

    for li, line in enumerate(lines):
        top = (1 + li * (ROWS + 2)) * scale
        for ci, ch in enumerate(line):
            rows = bitmaps.get(ch)
            if rows is None:
                continue
            for r in range(ROWS):
                for c in range(COLS):
                    if (rows[r] >> (7 - c)) & 1:
                        for dy in range(scale):
                            for dx in range(scale):
                                put((1 + ci * COLS + c) * scale + dx,
                                    top + r * scale + dy, (0, 0, 0))
        # a baseline rule, to make the 8x10 cell legible
        for x in range(pad, width - pad):
            put(x, top + (ROWS - 1) * scale + scale - 1, (200, 200, 200))
    write_png(path, width, height, grid)

GRAPHICS_FIRST, GRAPHICS_LAST = 0x00, 0x1F
GRAPHICS_EXTRA = (0x7F,)          # the hatch/checkerboard glyph


def write_glyph_sheet(path, bitmaps, scale=5, cols=6, pad=12):
    """Every graphics glyph, each labelled with its code, for mapping by eye.

    The labels are drawn from the ROM's own glyphs, so the sheet is rendered
    entirely by the machine's font -- including the digits of the codes.
    """
    codes = list(range(GRAPHICS_FIRST, GRAPHICS_LAST + 1)) + list(GRAPHICS_EXTRA)
    cell_w = COLS * scale + pad
    cell_h = ROWS * scale + pad + ROWS * 2
    rows_n = (len(codes) + cols - 1) // cols
    width, height = cols * cell_w + pad, rows_n * cell_h + pad
    grid = [[(255, 255, 255)] * width for _ in range(height)]

    def blit(glyph_rows, x, y, s):
        for r in range(ROWS):
            for c in range(COLS):
                if (glyph_rows[r] >> (7 - c)) & 1:
                    for dy in range(s):
                        for dx in range(s):
                            px, py = x + c * s + dx, y + r * s + dy
                            if 0 <= px < width and 0 <= py < height:
                                grid[py][px] = (0, 0, 0)

    def label(text, x, y, s=2):
        for i, ch in enumerate(text):
            glyph_rows = bitmaps.get(ord(ch))
            if glyph_rows:
                blit(glyph_rows, x + i * (COLS * s + 2), y, s)

    for i, code in enumerate(codes):
        cx = pad + (i % cols) * cell_w
        cy = pad + (i // cols) * cell_h
        blit(bitmaps[code], cx, cy, scale)
        label("%02X" % code, cx, cy + ROWS * scale + pad // 2)

    write_png(path, width, height, grid)
    return codes


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Build the web font family from the Osborne 1 character generator.")
    ap.add_argument("--rom", default=str(DEFAULT_ROM),
                    help="character generator ROM (default: the MAME romset copy)")
    ap.add_argument("--outdir", default=str(OUT_DIR),
                    help="where the font files live (default: site/assets/fonts)")
    ap.add_argument("--check", action="store_true",
                    help="verify the committed files are up to date (CI mode)")
    ap.add_argument("--specimen", metavar="FILE.png",
                    help="also render a specimen sheet, for a human to look at")
    ap.add_argument("--glyph-sheet", metavar="FILE.png",
                    help="render the 0x00-0x1F graphics set + 0x7F, labelled, "
                         "so the Unicode mapping can be checked by eye (#97)")
    args = ap.parse_args(argv)

    rom = Path(args.rom)
    data = rom.read_bytes()
    crc = "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)

    from io import BytesIO
    artefacts, bitmaps = {}, None
    for columns in COLUMNS:
        font, bitmaps, x = build_font(data, rom.name, crc, columns)

        problems = verify(font, bitmaps, x)
        if problems:
            for p in problems:
                print("FAIL %s" % p)
            print("refusing to write a font that does not match the ROM")
            return 1
        print("verified: %d columns at %d%% dot width, all %d glyphs "
              "round-trip to the ROM's bits"
              % (columns, round(100 * x / SCALE), LAST - FIRST + 1))

        ttf_bytes = BytesIO()
        font.save(ttf_bytes)
        font.flavor = "woff2"
        woff_bytes = BytesIO()
        font.save(woff_bytes)
        artefacts["osborne1-%d.ttf" % columns] = ttf_bytes.getvalue()
        artefacts["osborne1-%d.woff2" % columns] = woff_bytes.getvalue()

    # The specimen sheet and the glyph sheet describe the ROM, not a display
    # width, so they are written once from the (identical) bitmaps.
    if args.specimen:
        write_specimen(args.specimen, bitmaps)
        print("wrote " + args.specimen)

    if args.glyph_sheet:
        codes = write_glyph_sheet(args.glyph_sheet, bitmaps)
        print("wrote %s (%d graphics glyphs)" % (args.glyph_sheet, len(codes)))

    out = Path(args.outdir)

    if args.check:
        stale = []
        for name, want in sorted(artefacts.items()):
            path = out / name
            if not path.exists() or path.read_bytes() != want:
                stale.append(name)
        if stale:
            print("stale font file(s): " + ", ".join(stale))
            print("run: tools/romfont.py")
            return 1
        print("font files OK: %s" % ", ".join(sorted(artefacts)))
        return 0

    out.mkdir(parents=True, exist_ok=True)
    for name, blob in sorted(artefacts.items()):
        (out / name).write_bytes(blob)
        print("wrote %s (%d bytes)" % (out / name, len(blob)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
