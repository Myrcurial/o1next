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

What it emits for the graphics set (#97)
----------------------------------------
The 0x00-0x1F block glyphs, 0x20 and the 0x7F hatch are deliberately **not** in
the text family: they are Osborne's own encoding, not Unicode, so each glyph
would have to be *identified* rather than assumed.  But they are what the machine
*draws* with -- the AUTOCPM/AUTOST boot art is a wall of these characters -- so
they ship as a second face, ``osborne1-art-*``, in which each glyph is mapped to
its charcode **+ 65**:

    'A' (0x41) draws glyph 0x00 ... 'a' (0x61) draws the blank ... U+00C0 -> 0x7F

That is the arithmetic the ROM's own loader does (`sui 65` -- subtract 65 from
every byte), so art authored in the face is art the machine can print.  Type the
art as text, switch the font, and the picture appears; the cell is 8x10 and one
line is exactly one em, so at line-height 1.0 the cells tile with no seams.

It sidesteps #97 rather than pre-empting it: this face needs the *arithmetic*,
#97 needs the *identification*, and the identification is a job of looking at the
art -- which is what this renders.  `--art-sheet` is the authoring key, every
glyph labelled with the character that draws it.

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

# The graphics set (#97) as an authoring face.  0x00-0x1F are the block glyphs,
# 0x7F is the hatch, and 0x20 is the blank cell the art uses for "no ink".
#
# The art is authored as a *wall of text* -- one character per cell, which is
# what AUTOCPM.ASM is -- and read back at run time with `sui 65` (subtract 65
# from every byte).  So each glyph is mapped to its charcode **+ 65**: 'A'
# (0x41) draws glyph 0x00, 'a' (0x61) draws the blank, and 0x7F lands on
# U+00C0 because 0x7F + 65 = 0xC0.  That is the same arithmetic the loader
# does, which is the point: type the art, switch the font, see the picture.
ART_CODES = tuple(range(0x00, 0x21)) + (0x7F,)
ART_OFFSET = 65
ART_LAST_ASCII = 0x7F   # codepoints above this need a non-ASCII key

# The art range above is only half the face.  Art also carries *text* -- ROM
# 2.00's boot screen has "press return to begin" nested in the X's counter, and
# those are the machine's ordinary letters, not graphics glyphs.  `sui 65`
# cannot reach them: 'p' is 0x70, and 0x70 - 65 = 0x2F is not a glyph.
#
# So the face maps the whole printable range, with the graphics at 0x41-0x61 and
# everything else to the machine's own glyph for that code.  That is exactly the
# split the ROM's printer needs too: 0x41-0x61 means "graphics, subtract 65",
# anything else means "print it".
ART_TEXT_FIRST, ART_TEXT_LAST = 0x20, 0x7E


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
                # OpenType's achVendID is exactly four bytes, so the name's
                # six-byte form cannot go here.  `o1nx` is the four-byte form,
                # the same `nx` qualifier the MAME machine uses (#228).
                achVendID="o1nx")
    fb.setupPost()
    glyphs = [(ch, ch, names[ch]) for ch in sorted(names)]
    return fb.font, bitmaps, x, glyphs


def build_art_font(rom_data, rom_name, crc, columns=BASE_COLUMNS):
    """The graphics set only, as an *authoring* face (#97).

    Same glyphs, same cell, same metrics as the text family -- but only the 34
    graphics charcodes, each mapped to **charcode + 65**.  Type the art as a
    wall of text, switch to this font, and the picture appears; the arithmetic
    is the same `sui 65` the ROM loader does.

    It is deliberately *not* a Unicode mapping.  The glyphs are Osborne's own
    encoding and #97 has not identified them yet -- but an authoring face does
    not need them identified, it needs the arithmetic.  That is also why it can
    ship before #97 finishes, and why it makes #97 easier: the identification is
    a job of *looking at the art*, and this is what renders the art.
    """
    x = xscale(columns)
    bitmaps = decode_rom(rom_data)

    # Two halves, one face.  The graphics: charcode 0x00-0x20 and 0x7F, each at
    # charcode + 65.  The text: every other printable codepoint, as the machine's
    # own glyph for that code -- which is what the letters inside the X need.
    glyphs = [(ch, ch + ART_OFFSET, "art%02X" % ch) for ch in ART_CODES]
    taken = {cp for _, cp, _ in glyphs}
    glyphs += [(cp, cp, "text%02X" % cp)
               for cp in range(ART_TEXT_FIRST, ART_TEXT_LAST + 1)
               if cp not in taken]
    # Keyed by glyph *name*, not by charcode: the graphics blank (charcode 0x20)
    # and the text space (codepoint 0x20) would otherwise collide, and the cmap
    # would reference a glyph that never got built.
    glyphs.sort(key=lambda t: t[1])
    cmap = {cp: name for _, cp, name in glyphs}
    ch_of = {name: ch for ch, _, name in glyphs}

    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder([".notdef"] + [name for _, _, name in glyphs])
    fb.setupCharacterMap(cmap)

    glyf = {".notdef": glyph_from_rows(notdef_rows(), x)}
    metrics = {".notdef": (COLS * x, 0)}
    for name, ch in ch_of.items():
        glyf[name] = glyph_from_rows(bitmaps[ch], x)
        metrics[name] = (COLS * x, 0)
    fb.setupGlyf(glyf)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=(ROWS - 1) * SCALE, descent=-SCALE)

    import calendar
    fixed = 2082844800 + calendar.timegm((2026, 10, 8, 0, 0, 0, 0, 0, 0))
    fb.setupHead(unitsPerEm=UPEM, created=fixed, modified=fixed)

    fam = "Osborne 1 Art %d" % columns
    fb.setupNameTable({
        "familyName": fam,
        "styleName": "Regular",
        "uniqueFontIdentifier": "%s; %s %s" % (fam, rom_name, crc),
        "fullName": fam,
        "psName": "Osborne1-Art-%d-Regular" % columns,
        "version": "Version 1.000",
        "description": (
            "The Osborne 1 character generator (UA15, 2716) as an ART face: the"
            " graphics glyphs 0x00-0x1F, 0x20 and 0x7F each mapped to its"
            " charcode + 65, so a wall of art text renders as the picture (the"
            " ROM's loader does `sui 65`) -- 'A' draws glyph 0x00, 'a' the blank,"
            " U+00C0 glyph 0x7F -- AND every other printable codepoint mapped to"
            " the machine's own glyph for that code, because art also carries"
            " text ('p' is 0x70, and 0x70 - 65 is not a glyph). Decoded from %s"
            " (CRC32 %s). Advance is exactly the 8-pixel cell and one line is"
            " exactly one em, so set line height to 1.0 and the cells tile with"
            " no seams. This is the %d-column aspect: %d%% horizontal dot width."
            % (rom_name, crc, columns, round(100 * x / SCALE))),
    })
    fb.setupOS2(sTypoAscender=(ROWS - 1) * SCALE, sTypoDescender=-SCALE,
                sTypoLineGap=0, usWinAscent=(ROWS - 1) * SCALE,
                usWinDescent=SCALE, sxHeight=5 * SCALE, sCapHeight=7 * SCALE,
                # Four bytes, as above -- see the note in build_font().
                achVendID="o1nx")
    fb.setupPost()
    return fb.font, bitmaps, x, glyphs


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


def verify(font, bitmaps, x, glyphs):
    """Round-trip every glyph, and check the cmap, against the ROM.

    ``glyphs`` is the ``(charcode, codepoint, name)`` list a builder returns, so
    one check covers all three cases: the text family, where the codepoint *is*
    the charcode; the art face's graphics half, where it is the charcode + 65;
    and the art face's text half, where it is the charcode again.

    The cmap half matters as much as the outline half.  A font whose glyphs are
    perfect but whose mapping is off by one draws a *plausible* picture that is
    simply wrong, which is far harder to notice than a blank cell.
    """
    glyf = font["glyf"]
    cmap = font.getBestCmap()
    problems = []
    for ch, cp, name in glyphs:
        got = rasterise_glyph(glyf[name], x)
        if got != bitmaps[ch]:
            problems.append("glyph 0x%02X (%s): outlines do not match the ROM"
                            % (ch, name))
        if cmap.get(cp) != name:
            problems.append("U+%04X maps to %r, not %r"
                            % (cp, cmap.get(cp), name))
    return problems


# --------------------------------------------------------------------------
# specimen sheet: the human check
# --------------------------------------------------------------------------

def write_png(path, width, height, rows):
    """Encode a PNG.  Writes it to ``path``; returns the bytes either way."""
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
    if path is not None:
        open(path, "wb").write(png)
    return png


SPECIMEN_LINES = [
    "o1next",
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


def write_art_sheet(path, bitmaps, scale=5, cols=6, pad=12):
    """The graphics set, each glyph labelled with the CHARACTER that draws it.

    This is the authoring key for the `osborne1-art-*` faces: type the character
    in the label, get the glyph above it.  Everything on the sheet -- the glyphs
    and the labels alike -- is drawn from the ROM's own glyphs, so the sheet is
    rendered by the machine's font and cannot drift from it.

    0x7F has no ASCII character at +65 (it lands on U+00C0), so it is labelled
    by its codepoint instead; and the blank cell (0x20 -> 'a') shows nothing,
    which is what it draws.
    """
    codes = list(ART_CODES)
    cell_w = COLS * scale + pad
    cell_h = ROWS * scale + pad * 2 + ROWS * 2
    rows_n = (len(codes) + cols - 1) // cols
    caption = "GRAPHICS SET: GLYPH = CHARACTER - 65"
    caption_h = ROWS * 4
    # The caption is drawn in the ROM's own glyphs too, so the sheet has to be
    # at least as wide as the caption -- 8 pixels per character at scale 2.
    width = max(cols * cell_w + pad, len(caption) * (COLS * 2 + 2) + pad)
    height = caption_h + rows_n * cell_h + pad
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

    label(caption, pad, pad, 2)

    for i, code in enumerate(codes):
        cp = code + ART_OFFSET
        cx = pad + (i % cols) * cell_w
        cy = caption_h + (i // cols) * cell_h
        blit(bitmaps[code], cx, cy, scale)
        text = chr(cp) if 0x21 <= cp < 0x7F else "%02X" % cp
        label(text, cx, cy + ROWS * scale + pad // 2)

    return write_png(path, width, height, grid), codes


def emit_font(artefacts, font, stem):
    """Save one font as .ttf and .woff2 into the artefact map."""
    from io import BytesIO
    ttf = BytesIO()
    font.save(ttf)
    font.flavor = "woff2"
    woff = BytesIO()
    font.save(woff)
    artefacts[stem + ".ttf"] = ttf.getvalue()
    artefacts[stem + ".woff2"] = woff.getvalue()


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
    ap.add_argument("--art-sheet", metavar="FILE.png",
                    help="render the graphics set labelled with the CHARACTER "
                         "that draws each glyph -- the authoring key for the "
                         "osborne1-art-* faces")
    args = ap.parse_args(argv)

    rom = Path(args.rom)
    data = rom.read_bytes()
    crc = "%08x" % (zlib.crc32(data) & 0xFFFFFFFF)

    from io import BytesIO   # noqa: F401  (kept: emit_font owns the buffer)
    artefacts, bitmaps = {}, None
    for columns in COLUMNS:
        font, bitmaps, x, glyphs = build_font(data, rom.name, crc, columns)

        problems = verify(font, bitmaps, x, glyphs)
        if problems:
            for p in problems:
                print("FAIL %s" % p)
            print("refusing to write a font that does not match the ROM")
            return 1
        print("verified: text %d columns at %d%% dot width, %d glyphs "
              "round-trip to the ROM's bits"
              % (columns, round(100 * x / SCALE), len(glyphs)))
        emit_font(artefacts, font, "osborne1-%d" % columns)

        art, _, _, art_glyphs = build_art_font(data, rom.name, crc, columns)
        problems = verify(art, bitmaps, x, art_glyphs)
        if problems:
            for p in problems:
                print("FAIL %s" % p)
            print("refusing to write a font that does not match the ROM")
            return 1
        n_art = sum(1 for _, cp, _ in art_glyphs
                    if 0x41 <= cp <= 0x61 or cp == 0xC0)
        print("verified: art  %d columns, %d glyphs -- %d graphics at charcode "
              "+ %d, %d text glyphs for the rest"
              % (columns, len(art_glyphs), n_art, ART_OFFSET,
                 len(art_glyphs) - n_art))
        emit_font(artefacts, art, "osborne1-art-%d" % columns)

    # The specimen sheet and the glyph sheet describe the ROM, not a display
    # width, so they are written once from the (identical) bitmaps.
    if args.specimen:
        write_specimen(args.specimen, bitmaps)
        print("wrote " + args.specimen)

    if args.glyph_sheet:
        codes = write_glyph_sheet(args.glyph_sheet, bitmaps)
        print("wrote %s (%d graphics glyphs)" % (args.glyph_sheet, len(codes)))

    if args.art_sheet:
        _, codes = write_art_sheet(args.art_sheet, bitmaps)
        print("wrote %s (%d glyphs, labelled character = glyph + %d)"
              % (args.art_sheet, len(codes), ART_OFFSET))

    # The authoring key for the art face is a committed artefact, not a
    # convenience: it is the only place the character -> glyph mapping is stated
    # for a human, so --check keeps it in step with the fonts.
    artefacts["osborne1-art-sheet.png"] = write_art_sheet(None, bitmaps)[0]

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
