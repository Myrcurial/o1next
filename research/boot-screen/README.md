# boot-screen — the authored art for ROM 2.00's boot screen (#83)

The **hand-drawn boot-screen art** for ROM 2.00, authored in the machine's own
graphics characters and rendered through the character generator. This is a
**design source**, not analysis, which is why it is kept here rather than in
`docs/` — the same reason `research/pictures/` is kept.

| File | What it is |
|---|---|
| `o1ng-art.txt` | the **O1NG** version: 125 × 28 cells, one character per cell. SHA-256 `a92bf28e81b54c58f59c48ab16f090e2d26c4e8d3705ed0cfcda7dd10bb1f9ba` |
| `o1ng-art.png` | the same art rendered with the ROM's own glyphs (UA15), for reading |

## How it is authored, and how to read it

Each character is one cell, and the character's code **minus 65** is the glyph
index — which is exactly the arithmetic the ROM's own loader does (`sui 65`).
So `A` (0x41) is glyph 0x00, `a` (0x61) is the blank cell, and the art is a wall
of text that renders as a picture in the `osborne1-art-*` faces built by
`tools/romfont.py` (`tools/README.md`).

To see it: open the `.txt` in TextEdit, select all, set the font to
**Osborne 1 Art 52**, and set line height to 1.0 so the 8×10 cells tile with no
seams. `o1ng-art.png` is the same thing already rendered.

## What it is for, and what it costs

`docs/o1-rom-2.0.md` §2.3 sizes ROM 2.00's contents at 7681 bytes, leaving **511
bytes of the ROM window spare** — which is where the boot screen goes. This art
is the design side of that budget; the byte side is measured, not guessed:

| Piece | Bytecode |
|---|---|
| the whole art (125 × 28) | 626 B |
| the O ring, cols 26–51 | 169 B |
| the 1NG, cols 55–124 | 511 B |
| the 7 hatch rules | 29 B — regenerable by a loop, so not stored |

The art is drawn in horizontal stripes — **14 content rows interleaved with 14
blank ones** — which is both the look and most of why it compresses.

## Measured geometry

| Piece | Columns | Width |
|---|---|---|
| hatch rules | 0–51 | 52 (26 of them to the *left* of the O) |
| O ring | 26–51 | 26 |
| `1` | 55–68 | 14 |
| `N` | 71–96 | 26 |
| `G` | 99–124 | 26 |

Kerning as drawn: **O→1 = 3, 1→N = 2, N→G = 2.** With the maintainer's rule that
the N's right serifs and the E's left serifs *share* the kerning space, **N→E = 0**
and E and X carry the G's width while T is narrower.

The letters are measured independently of the hatch: the 26 columns of rule to
the left of the O are never counted in a letter's width.

## Why the long version is being redrawn narrower

- **O1NG = 99 columns** (125 with the hatch) — fits the video buffer's **128**.
- **O1NEXT = 149 columns** — does not. With the O hard against column 0 the
  letters get columns 29–127, which is **99 columns** against a 120-column word.

So the long version has to shed **21 columns, about 18%**: N/E/X at roughly 21
wide, T at 18, the `1` at 11. That is the target `o1next-art.txt` is drawn to.

## Provenance

Authored by the maintainer on 2026-10-14, in the `osborne1-art-*` face that
`tools/romfont.py` builds from the character generator ROM. `o1ng-art.txt` was
recovered from `/tmp/o1ng-art.txt` after an RTF round-trip; the copy here is the
authority.
