# boot-screen — the authored art for ROM 2.00's boot screen (#83)

The **hand-drawn boot-screen art** for ROM 2.00, authored in the machine's own
characters and rendered through the character generator. This is a **design
source**, not analysis, which is why it is kept here rather than in `docs/` — the
same reason `research/pictures/` is kept.

| File | What it is |
|---|---|
| `o1ng-art.txt` | the **O1NG** version: 125 × 28 cells. SHA-256 `a92bf28e81b54c58f59c48ab16f090e2d26c4e8d3705ed0cfcda7dd10bb1f9ba` |
| `o1ng-art.png` | the same, rendered with the ROM's glyphs |
| `o1next-art.txt` | the **O1NEXT** version: 153 × 27 cells, with *"osborne 1 next rom 2.0 2026"* and *"press return to begin"* nested in the X's counter. SHA-256 `a3617203212e193651a8dae44b3fdb030f0f5051fe629250ac2ccd0abdacd42a` |
| `o1next-art.png` | the same, rendered with the ROM's glyphs |
| `o1next-frame.png` | **the screen itself** — the 4096-byte frame rendered with the chargen. All 32 rows, so the validity trailer is visible at the bottom right; on the machine rows 24–31 are off-screen |

## How it is authored, and how to read it

Each character is one cell. **Two mappings live in one file**, and the split is
the ROM's own:

- **0x41–0x61 (`A`–`a`) is graphics.** Character code **minus 65** is the glyph
  index — the same `sui 65` the ROM's loader does. `A` draws glyph 0x00, `a` is
  the blank cell, and 0x7F lands on U+00C0.
- **Everything else printable is text**, and the glyph *is* the code. This is not
  a convenience: `sui 65` cannot reach the lettering at all, because `p` is 0x70
  and 0x70 − 65 = 0x2F is not a glyph.

**Which is why the captions are lowercase.** `A`–`Z`, `[`, `\`, `]`, `^`, `_`, `` ` ``
and `a` are all inside the graphics range, so a capital is read as a glyph index
and draws as a block — `Osborne` would come out as four blocks and a letter. The
version caption is `osborne 1 next rom 2.0 2026` for exactly that reason. (`a` is
the blank cell, so the letter `a` cannot be written at all; neither caption needs
one.)

So the ROM's printer branches on the byte, and the `osborne1-art-*` faces built
by `tools/romfont.py` map both halves — 34 graphics glyphs plus 62 text glyphs.

To see it: open the `.txt` in TextEdit, select all, set the font to
**Osborne 1 Art 52**, and set line height to 1.0 so the 8×10 cells tile with no
seams. The `.png` files are the same thing already rendered.

**Verified end to end:** the 4131 characters of `o1next-art.txt`, rendered through
`osborne1-art-52`, reproduce the chargen's 8×10 bits with **0 differing**.

## O1NEXT — measured

| Piece | Columns | Width |
|---|---|---|
| hatch rules | 0–45 | 26 columns of them to the *left* of the O |
| O ring | 26–46 | 21 |
| `1` | 47–59 | 13 |
| `N` | 61–82 | 22 |
| `E` | 84–102 | 19 |
| `X` | 104–127 | 24 |
| `T` | 129–152 | 24 |
| the message | 106–132 / 112–132, rows 12 and 14 | inside the X's counter |

Kerning: **O→1 = 0**, then 1 → N → E → X → T at **1 each**.

**The logo is 26–152 = 127 columns, and fits the 128-column video buffer** with a
column to spare. The *art* is 153 only because the 26 columns of rule to the left
of the O are drawn — and those are consumed as the O slides, so they do not need
storing (a rule is a loop, 29 B).

## The animation: one viewport slide

The art is 1.6× the 80-column viewport, so it can never all be on screen at once.
Sliding the viewport is the whole animation:

| viewport left | shows VRAM | O | 1 | N | E | X | T | message |
|---|---|---|---|---|---|---|---|---|
| 0 | 0–79 | full | full | part | – | – | – | – |
| 13 | 13–92 | full | full | full | part | – | – | – |
| **26** | **26–105** | full | full | full | full | part | – | – |
| 40 | 40–119 | part | full | full | full | part | – | part |
| 48 | 48–127 | – | part | full | full | full | – | full |
| 73 | 73–152 | – | – | part | full | full | full | full |

At viewport 26 — *"viewport column 1 aligned with VRAM 27"* — the O sits at screen
0–20, having consumed the hatch exactly as described. **But the T and the message
are not on screen there:** the message needs viewport 48 and the T needs 73.

**The fix is placement, not a longer slide.** The hatch is *generated*, so the
logo belongs at buffer column 0 rather than 26. At viewport 26 the visible range
is then the logo's own columns 26–105 — N, E, X, the message (at 82–101) and most
of the T.

## What it costs

Bytecode (glyph 1 B, `7F,n,c` 3 B, skip 2 B, row-repeat 2 B, newline 1 B):

| | O1NG | O1NEXT |
|---|---|---|
| whole art | 626 B | 831 B |
| the logo alone | — | 816 B |
| O ring | 169 B | 168 B |
| letters | `1`+`NG` as one run: 192 + 251 + 196 | 188 / 235 / 152 / 270 / 190 |
| the message | — | 37 B, as text glyphs |
| the hatch rules | 29 B | 29 B |

Both are over the **511-byte** ROM window spare (`docs/o1-rom-2.0.md` §2.3), and
`tools/research/rom2strokes.py` shows that *storing* it will not get there either:

| | the logo |
|---|---|
| raw bitmap, striped, 1 bit per sub-pixel | 857 B |
| RLE bytecode | 816 B |
| the exact rectangle cover | 784 B |

Every raster-shaped encoding lands in the same band, because the letters are heavy
(~40% of a letterform is ink) and the cover is dominated by diagonals — the X is 72
rectangles where it is structurally two strokes.

**It does not need to fit.** One window page is 4096 bytes and the video buffer is
128 × 32 = 4096 cells, so **one page is exactly one screen**; in bank 2 the window
and the video RAM are both visible, so a frame is one `LDIR` from `1000h` to
`F000h`. The frames live in the interposer's flash, not the ROM — about **40 bytes
of ROM**, and the animation is the viewport slide, which is a register write.

```
tools/research/rom2strokes.py --frame /tmp/frame.bin     # 4096 B, CRC32 898297ae
```

**One thing had to give.** The art is 153 columns and a screen is 128, so 25
columns cannot come along — and there are only two candidates: the 26 columns of
hatch to the left of the O, or the T. `--origin` defaults to 26, which places the
*logo* at column 0 and keeps it whole; the hatch is a rule loop and can be drawn
back at run time, and the O sliding off the left edge reads as the logo stretching
with or without it.

## The frame validates itself, and the fallback is free

The frame is *someone else's file* — the interposer's flash is updatable and a
hand-built image will get it wrong — so it carries a marker in the rows nobody can
see (rows 24–31 are off-screen): `O1NG` at `0FF8h`, a 16-bit sum at `0FFCh`.

If it is missing or wrong, the monitor leaves **`o1next - press return`** on the
screen. That costs nothing, because ROM 2.0 replaces the stock sign-on rather than
adding to it: 21 bytes of text plus 6 bytes of code, against `IMSG`'s **182** — so
the fallback frees 155 bytes and pays for its own check out of them.

Order at boot: print the text first, page the frame in, check the trailer, and blit
over the text if it is right.

## Provenance

Authored by the maintainer on 2026-10-14, in the `osborne1-art-*` face that
`tools/romfont.py` builds from the character generator ROM. The copies here are
the authority.
