#!/usr/bin/env python3
"""rom2strokes.py -- read the authored boot-screen art as geometry, and cost it.

WHY THIS EXISTS
    ROM 2.00's boot screen is hand-drawn (`research/boot-screen/`) and has to be
    produced by the machine.  `docs/o1-rom-2.0.md` section 2.3 leaves **497 bytes
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
    section 4.4), so a frame is one `LDIR` from `1000h` to `F000h`, and the frame
    lives in the Pico's own flash rather than the ROM.  `--frame` writes it.

    **The frame is two halves, and each validates itself** (2026-10-15, #247 step
    8).  The O1's video cell is nine bits -- eight of character and one of
    brightness -- and the ninth is not in the video RAM: it is a separate 4K x 1
    array that `OUT (02h)` pages into `F000-FFFF`, and its low seven bits read
    high because they are not physically present.  So the artifact is **8192
    bytes, the character half then the attribute half**, each half a window page
    with its own trailer at its own `0FF8h` -- either half validates without the
    other -- and v1.0's attribute half is all `FFh`, every cell bright.  That is
    a *frame*, not a limit of the format: the ROM blits the attribute half
    whenever it validates, so a later frame can carry dim accents with no ROM
    change.  The contract is `docs/rom-pico-protocol.md` sections 4.1 and 5.

Usage:
    tools/research/rom2strokes.py                  # the stripe proof and the costs
    tools/research/rom2strokes.py --frame OUT.bin  # 8192 bytes: two halves
    tools/research/rom2strokes.py --frame OUT.bin --half attrs   # just one half
    tools/research/rom2strokes.py --verify OUT.bin # do its trailers hold?
    tools/research/rom2strokes.py --logo OUT.png   # the site masthead
    tools/research/rom2strokes.py --check          # fail if the masthead is stale

    --frame no longer feeds a committed asset, and --check no longer checks one.
    `firmware/rom-service/frame.bin` was **retired on 2026-10-16**: the boot screen
    became the animation the RP2354B plays (`tools/bootsplash/`,
    `firmware/rom-service/boot-animation.bin`, #247's W5), and the generator and the
    byte-for-byte check went with it.  What remains here is a converter -- art text
    to a frame, a frame validated off the disk -- and the masthead, whose source is
    still `research/boot-screen/`.
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
VISIBLE = 24                              # rows 24-31 are off-screen
FRAME = STRIDE * ROWS                     # 4096: one buffer, and one window page

# --- the frame's trailer --------------------------------------------------
#
# The frame is *someone else's file*: the interposer's flash is updatable, and a
# hand-built image will get this wrong.  So the frame carries its own validity
# marker in the rows nobody can see -- rows 24-31 are off-screen -- and the
# monitor checks it before blitting.  Without it a bad image puts garbage on the
# screen and there is no way back.
#
#   frame[4088:4094]  b'O1NEXT'                 the magic, six bytes
#   frame[4094:4096]  the 16-bit sum of 0..4087, little-endian
#
# The trailer is eight bytes either way.  The magic grew from four bytes to six
# by consuming the two reserved bytes that used to sit at 4094, so the checksum
# definition does not move: it still covers exactly the 4088 bytes before the
# trailer.  The monitor's compare grows from four bytes to six (#228).

MAGIC = b'O1NEXT'
TRAILER = 8
TRAILER_AT = FRAME - TRAILER

# --- the frame's two halves ------------------------------------------------
#
# The artifact is **8192 bytes: two 4096-byte halves, characters then
# attributes**, because the O1's video cell is nine bits and the ninth is not in
# the video RAM -- it lives in a separate 4K x 1 array that `OUT (02h)` pages
# into `F000-FFFF` (#247 step 8; `docs/rom-pico-protocol.md` section 5).  Each
# half is one window page, so `PRESENT(1)` and `PRESENT(2)` deliver them one at a
# time, and **each half carries the same trailer at its own `0FF8h`**, so either
# validates without the other.
#
# v1.0's attribute half is all `FFh`, and that is a frame rather than a limit of
# the format: bit 7 set is *bright* (the renderer is `BIT(attr,7) ? 2 : 1`) and
# the array's low seven bits read high because they are not physically there, so
# `FFh` is the array's own image of an all-bright screen, byte for byte.

ATTR_BRIGHT = 0xFF
HALF_NAMES = ('chars', 'attrs')

# --- the fallback sign-on -------------------------------------------------
#
# If the frame is missing or malformed, the monitor must still say something
# useful.  It does not cost anything extra, because ROM 2.0 *replaces* the stock
# sign-on rather than adding to it: IMSG is 182 bytes, and this is 21.

FALLBACK = 'o1next - press return'
FALLBACK_LEN = len(FALLBACK)          # OSTR stops on a byte with bit 7 set, so
IMSG_LEN = 182                        # the string is its own terminator

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


def png_bytes(width, height, rows, alpha=False):
    """A minimal PNG, as bytes -- stdlib only, this tool must not need the venv.

    Split out from `write_png` so a render can be compared without touching the
    filesystem: `check_logo()` re-renders in memory.  The filter is fixed (none)
    and the compression is fixed (level 9), which is what makes the bytes
    comparable at all -- `tools/romfont.py` writes and compares its PNG the same
    way, for the same reason.
    """
    import struct
    raw = bytearray()
    for row in rows:
        raw.append(0)
        for px in row:
            raw.extend(px)

    def chunk(tag, payload):
        return (struct.pack(">I", len(payload)) + tag + payload +
                struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF))

    colour = 6 if alpha else 2
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, colour, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def write_png(path, width, height, rows, alpha=False):
    """A minimal PNG writer, stdlib only -- this tool must not need the venv."""
    open(path, "wb").write(png_bytes(width, height, rows, alpha))


def logo_grid(rows, ink=(0xF1, 0xF4, 0xF6)):
    """The art as the site's masthead: light glyphs on a transparent ground.

    The site's header is the machine's blue front panel (`--blue`, #687898), and
    the Osborne's CRT was **paper white** -- dark characters on a light screen.
    On a blue band that reads wrong, so the masthead is the *inverse* of the
    screen: light glyphs, and no background at all, so the band shows through.

    **The masthead is the art's *graphics*, and only its graphics.**  The art
    carries two strings that belong to the boot screen alone -- the version
    caption `osborne 1 next rom 2.0 2026` (row 12) and the prompt `press return
    to begin` (row 14) -- and both are *text* in the art's own alphabet, while
    every mark of the drawing is a graphics glyph.  So dropping the text glyphs
    leaves the wordmark exactly, and a caption added to the art later cannot
    leak into the masthead.

    Nothing is lost by dropping them, because the art spells a blank cell `a`,
    which *is* a text-range character: a dropped cell and a blank one draw the
    same nothing.  (`a` is also why no caption can contain the letter `a` --
    see `research/boot-screen/README.md`.)
    """
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    rom = open(os.path.join(repo, 'tools', 'emulator-setup', 'roms',
                            'char.ua15'), 'rb').read()
    w, h = max(len(l) for l in rows) * 8, len(rows) * 10
    clear = (0, 0, 0, 0)
    grid = [[clear] * w for _ in range(h)]
    for r, line in enumerate(rows):
        for c, ch in enumerate(line):
            o = ord(ch)
            if GRAPHICS_FIRST <= o <= GRAPHICS_LAST:
                code = o - ART_OFFSET
            else:
                # Text is the boot screen's, not the masthead's.  `frame()` keeps
                # it -- there it *is* the sign-on; here it is dropped, which
                # covers both captions and everything outside the graphics range.
                continue
            for py in range(10):
                b = rom[py * 128 + code]
                for px in range(8):
                    if b >> (7 - px) & 1:
                        grid[r * 10 + py][c * 8 + px] = ink + (255,)
    return w, h, grid


def render_logo(rows, path, ink=(0xF1, 0xF4, 0xF6)):
    """The masthead, written to `path`.  See `logo_grid()` for what it is."""
    w, h, grid = logo_grid(rows, ink)
    write_png(path, w, h, grid, alpha=True)
    return path, w, h


def check_logo(rows, path):
    """Does the committed masthead still match the boot-screen art?

    Bytes rather than pixels, because the render is deterministic -- the glyphs
    come from a ROM in this repo, and the PNG is written with a fixed filter and
    a fixed compression level -- so the comparison is exact and cheap.  It is
    what `tools/romfont.py --check` does for the fonts, for the same reason: a
    masthead that drifts from its source should fail here rather than ship.

    Needs the standard library and two files in this repo, and nothing else, so
    it runs where the host tooling does not exist.
    """
    if not os.path.exists(path):
        print('masthead MISSING: %s' % path)
        return 1
    w, h, grid = logo_grid(rows)
    want = png_bytes(w, h, grid, alpha=True)
    have = open(path, 'rb').read()
    if have == want:
        print('masthead OK: %s matches the art (%dx%d, %d bytes)'
              % (path, w, h, len(want)))
        return 0
    print('masthead STALE: %s does not match the art' % path)
    print('  committed %d bytes, re-render %d bytes' % (len(have), len(want)))
    print('  run: tools/research/rom2strokes.py --logo %s' % path)
    return 1


def render_frame(buf, path):
    """Draw a frame with the character generator, so the screen can be *seen*.

    The glyphs are read straight out of the chargen ROM in its row-major-across-
    characters layout, the same one `tools/romfont.py` decodes.
    """
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    rom = open(os.path.join(repo, 'tools', 'emulator-setup', 'roms',
                            'char.ua15'), 'rb').read()
    w, h = STRIDE * 8, ROWS * 10
    grid = [[(255, 255, 255)] * w for _ in range(h)]
    for r in range(ROWS):
        for c in range(STRIDE):
            code = buf[r * STRIDE + c] & 0x7F
            for py in range(10):
                b = rom[py * 128 + code]
                for px in range(8):
                    if b >> (7 - px) & 1:
                        grid[r * 10 + py][c * 8 + px] = (0, 0, 0)
    write_png(path, w, h, grid)
    return path


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
    print('The ROM window spare is 497 B (docs/o1-rom-2.0.md section 2.3).  Every')
    print('raster-shaped encoding lands in the same band and none of them fits:')
    print('the letters are heavy, so there is little redundancy to exploit, and the')
    print('cover is dominated by diagonals -- the X is 72 rectangles where it is')
    print('structurally two strokes.')
    print()
    print('A *segment* model would be far smaller (the X is 2 strokes against')
    print('288 B, the T is 2 against 36 B) but no fitter here converged on one, so')
    print('that route is estimated, not demonstrated.')


def seal(body):
    """A half: the body, then six bytes of magic, then the 16-bit sum of it.

    The sum covers exactly the 4088 bytes *before* the trailer, which is why the
    magic could grow from four bytes to six by eating the two reserved bytes
    without moving the checksum's definition (#228).
    """
    if len(body) != TRAILER_AT:
        raise ValueError('a half is %d bytes of body, not %d'
                         % (TRAILER_AT, len(body)))
    checksum = sum(body) & 0xFFFF
    return bytes(body) + MAGIC + bytes([checksum & 0xFF, checksum >> 8])


def trailer_sum(half):
    """The 16-bit sum a half carries at `0FFEh`, little-endian, read back."""
    return half[TRAILER_AT + 6] | (half[TRAILER_AT + 7] << 8)


def chars_half(rows, origin):
    """The character half: the art placed so that `origin` lands at column 0.

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

    # The validity marker, in rows nobody can see -- and its own trailer, because
    # a half that arrives alone must be able to say whether it is intact.
    return seal(buf[:TRAILER_AT])


def attrs_half():
    """The attribute half: every cell bright, and its own trailer.

    `FFh` rather than `80h`, because `FFh` is what the array *reads back* for a
    bright cell -- its low seven bits are not physically present and read high --
    so this half is the array's own image of an all-bright screen, byte for byte.
    The eight trailer bytes sit in cells 4088-4095, which are row 31: off-screen
    on the machine, exactly as the character half's are.
    """
    return seal(bytes([ATTR_BRIGHT]) * TRAILER_AT)


def halves(rows, origin):
    """Both halves, in the order the firmware serves them -- `PRESENT(1)` and
    `PRESENT(2)` (`docs/rom-pico-protocol.md` section 4): characters, then
    attributes."""
    return chars_half(rows, origin), attrs_half()


def frame(rows, origin):
    """The whole artifact: 8192 bytes, two self-validating 4096-byte halves."""
    return b''.join(halves(rows, origin))


def check_half(half, name):
    """`(ok, message)` -- does this half carry a good trailer at its own `0FF8h`?

    The check is the monitor's own and nothing more: six bytes of magic, then a
    16-bit sum of everything before them.  That is deliberate rather than lazy --
    the trailer is *also* the "is a frame there?" query, so a missing frame, an
    erased frame and a corrupt one are the same case, and there is no second
    failure mode to invent (`docs/rom-pico-protocol.md` section 6).
    """
    if len(half) != FRAME:
        return False, '%s: %d bytes, not %d' % (name, len(half), FRAME)
    if half[TRAILER_AT:] != seal(half[:TRAILER_AT])[TRAILER_AT:]:
        return False, ('%s: trailer %r + %04x, and the body sums to %04x'
                       % (name, bytes(half[TRAILER_AT:TRAILER_AT + len(MAGIC)]),
                          trailer_sum(half), sum(half[:TRAILER_AT]) & 0xFFFF))
    return True, '%s: %s + sum %04x' % (name, MAGIC.decode(), trailer_sum(half))


def check_frame(buf, name):
    """Validate a whole 8192-byte artifact, half by half.  True if both hold."""
    if len(buf) != 2 * FRAME:
        print('%s: %d bytes, not %d -- two halves' % (name, len(buf), 2 * FRAME))
        return False
    ok = True
    for i, half_name in enumerate(HALF_NAMES):
        good, message = check_half(buf[i * FRAME:(i + 1) * FRAME], half_name)
        print('  %-4s %s' % ('ok' if good else 'BAD', message))
        ok = ok and good
    return ok


def verify(path):
    """Validate a frame, or a single half, straight off the disk.  True if it
    holds.  This is the whole machine-free test: a half is self-describing, so
    nothing else -- not the art, not the chargen -- is needed to check one."""
    buf = open(path, 'rb').read()
    if len(buf) == 2 * FRAME:
        return check_frame(buf, path)
    good, message = check_half(buf, os.path.basename(path))
    print('  %-4s %s' % ('ok' if good else 'BAD', message))
    return good


# `check_asset()` -- the byte-for-byte check of the committed frame -- is gone.
# `firmware/rom-service/frame.bin` was retired on 2026-10-16 and there is nothing
# left for it to check: the boot screen is the animation the RP2354B plays, and its
# frames are validated by the machine's own trailer test (`--verify` here,
# `tools/bootsplash/selftest.js` there), not against an art file that no longer
# draws the screen.


def main(argv=None):
    repo = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    ap = argparse.ArgumentParser(
        description='Read the boot-screen art as geometry, and cost it.')
    ap.add_argument('--art', default=os.path.join(
        repo, 'research', 'boot-screen', 'o1next-art.txt'))
    ap.add_argument('--frame', metavar='OUT.bin',
                    help='write the frame: 8192 bytes, the character half then '
                         'the attribute half, each with its own trailer')
    ap.add_argument('--half', choices=HALF_NAMES,
                    help='with --frame, write just that one 4096-byte half -- the '
                         'shape PRESENT(1)/PRESENT(2) delivers')
    ap.add_argument('--verify', metavar='IN.bin',
                    help='validate a frame, or a single half, and exit non-zero '
                         'if a trailer does not hold; writes nothing')
    ap.add_argument('--origin', type=int, default=26,
                    help='art column to place at buffer column 0 (default 26, '
                         'the O\'s left edge: the logo fits, the hatch does not)')
    ap.add_argument('--png', metavar='OUT.png',
                    help='render the character half with the character generator, '
                         'so the screen can be looked at')
    ap.add_argument('--logo', metavar='OUT.png',
                    help='render the art as the site masthead: light glyphs on a '
                         'transparent ground, i.e. the screen inverted, because '
                         'the site header is the machine\'s blue panel')
    ap.add_argument('--check', action='store_true',
                    help='verify the committed masthead still matches the art, and '
                         'exit non-zero if it does not; writes nothing')
    args = ap.parse_args(argv)

    rows = load_art(args.art)

    # --verify and --check sit before `glyphs()` on purpose: both need the art
    # and files in this repo, and nothing else -- no o1art.py, no fontTools, no
    # host tooling.  So CI can run them, and a frame can be checked where the
    # art is not.
    if args.verify:
        return 0 if verify(args.verify) else 1

    if args.check:
        return check_logo(rows, os.path.join(repo, 'site', 'assets',
                                            'o1next-logo.png'))

    pat = {g: quadrant(b) for g, b in glyphs().items()}
    pat[BLANK] = 0
    report(rows, pat)

    if args.logo:
        path, w, h = render_logo(rows, args.logo)
        print()
        print('wrote %s: %dx%d, light glyphs on a transparent ground' % (path, w, h))
        print('  -- the screen inverted, for the site header\'s blue panel')

    if args.frame:
        chars, attrs = halves(rows, args.origin)
        image = {'chars': chars, 'attrs': attrs}.get(args.half, chars + attrs)
        with open(args.frame, 'wb') as fh:
            fh.write(image)
        print()
        if args.half:
            print('wrote %s: %d bytes = the %s half, one window page'
                  % (args.frame, len(image), args.half))
        else:
            print('wrote %s: %d bytes = two %d-byte halves, %s then %s'
                  % (args.frame, len(image), FRAME, HALF_NAMES[0], HALF_NAMES[1]))
        print('  CRC32    %08x' % (zlib.crc32(image) & 0xFFFFFFFF))
        print('  chars    %s + sum %04x -- the art, in glyph codes'
              % (MAGIC.decode(), trailer_sum(chars)))
        print('  attrs    %s + sum %04x -- all %02Xh, every cell bright'
              % (MAGIC.decode(), trailer_sum(attrs), ATTR_BRIGHT))
        print('  trailers in row %d at each half\'s own 0FF8h, off-screen '
              '(only %d rows are shown)' % (TRAILER_AT // STRIDE, VISIBLE))
        print()
        print('Each half validates itself, and that is checked here rather than')
        print('asserted -- the trailer is the only thing a monitor can test for:')
        if args.half:
            good, message = check_half(image, args.half)
            print('  %-4s %s' % ('ok' if good else 'BAD', message))
            ok = good
        else:
            ok = check_frame(image, args.frame)
        if not ok:
            print()
            print('the frame this tool just wrote does not validate -- that is a')
            print('bug in this tool, not a bad image')
            return 1
        print()
        print('The blit is one LDIR of 4096 bytes per half: 4096 x 21 T-states =')
        print('86016, which at 4 MHz is 21.5 ms.  Two halves are 43 ms, against a')
        print('floppy boot measured in seconds -- the frame is free in the only')
        print('sense that matters, which is that the machine cannot feel it.  The')
        print('bright fill of the attribute array is 21.5 ms more, and it happens')
        print('before the character half goes up: 24 of the array\'s 4096 cells')
        print('read dim at the sign-on, and they would show in a 4096-cell frame.')
        print()
        print('The fallback is free too, because it *replaces* the stock sign-on')
        print('rather than joining it:')
        print()
        print('    %s   %2d bytes of text, and the last character'
              % (FALLBACK.upper(), FALLBACK_LEN))
        print('                                  carries bit 7, which is the')
        print('                                  terminator OSTR looks for')
        print('    LDK DE,MSG / CALL OSTR        6 bytes of code')
        print('    ------------------------------')
        print('    total                        %2d bytes, against IMSG\'s %d'
              % (FALLBACK_LEN + 6, IMSG_LEN))
        print()
        print('So the fallback *frees* %d bytes, and pays for its own check.'
              % (IMSG_LEN - FALLBACK_LEN - 6))
        print()
        print('Order at boot: print the text first, then PRESENT(1), page the')
        print('character half in and check its trailer; if it is right, blit over')
        print('the text.  Then PRESENT(2) and the attribute half, which is blitted')
        print('if *it* validates and costs only the bright fill otherwise.  A')
        print('missing or hand-built image leaves the message on screen, which is')
        print('the whole point -- and the check is a compare against six bytes plus')
        print('a 16-bit sum, which is a loop over the page and about 20 ms.')
        print()
        print('This frame is not a committed asset.  The boot screen is now the')
        print('animation the RP2354B plays (tools/bootsplash/, and the asset at')
        print('firmware/rom-service/boot-animation.bin); the frame written here is a')
        print('conversion of this art, and nothing in the repo commits or checks it.')

        if args.png:
            render_frame(chars, args.png)
            print()
            print('rendered %s -- all 32 rows, so the trailer is visible at the'
                  % args.png)
            print('bottom right; on the machine rows %d-%d are off-screen.'
                  % (VISIBLE, ROWS - 1))
    return 0


if __name__ == '__main__':
    sys.exit(main())

