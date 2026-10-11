# The character generator's graphics set (#97)

The 2716 at **UA15** holds 128 glyphs of 8×10, and the first 32 of them
(`0x00–0x1F`) plus `0x7F` are **graphics characters** rather than letters. They
are the most stable thing in the ROM: the two char-gen variants differ in 93 of
128 glyphs, and the `0x00–0x1F` set is byte-identical in both
(`docs/o1-rom-variants.md`).

## They are block graphics, not box-drawing

The natural assumption is the IBM/CP437 line-drawing set (`─│┌┐└┘├┤┬┴┼`). That
assumption is wrong, and the manual says so in its own section title:

> **5.5 BLOCK GRAPHICS**
> — *Osborne 1 Technical Manual* p. 25

Looking at them confirms it — the sheet is committed beside this file as
`o1-chargen-graphics.png`, rendered by `tools/romfont.py --glyph-sheet`:

- **halves and quadrants** (solid blocks filling half or a quarter of the cell)
- **staircases and triangles** (the diagonal edges, drawn in steps because an
  8×10 cell has no other way to do a diagonal)
- a **circle** and a **cross**
- `0x7F`, a **checkerboard/hatch** fill — the glyph the site's wordmark is
  hatched with

So the candidates to compare against are **Block Elements** (`U+2580–U+259F`)
and Geometric Shapes, not the box-drawing block. That changes the mapping work
from "guess a line junction" to "measure a fraction of the cell", which is a
much better position: a block glyph can be *derived* from its coverage.

## What the set is for

It is what the machine used for graphics on a character display — the same
purpose as CP437's block and box characters, and the reason the O1 can draw
frames and charts at all. Two consequences for this project:

- **A video personality (#24) has to render these correctly**, not just the
  letters. `docs/o1-memory-io-map.md` §2a has the cell and attribute layout.
- **They are page furniture (#97).** A period site's rules, table borders,
  footer and bullets can be the machine's own characters instead of CSS
  borders.

## The mapping (open)

The mapping table is **not written yet, on purpose**: the issue asks for each
glyph to be identified by looking at it beside its candidate, and recorded with
its evidence rather than asserted. The sheet is the evidence side of that — it
is generated from the ROM, so it cannot drift from it.

Next: put the sheet beside a rendered Unicode Block Elements chart, identify
each of the 33, then add the table to `tools/romfont.py` so the codepoints ship
in the font.

## Why 64 columns (see also §2a)

The recovered AUTOCPM art is 64 columns wide and the O1's screen shows 52. That
is not a contradiction: video memory is **32 rows of 128 characters** and the
screen is a 52×24 **window** onto it, so a 64-column drawing simply extends past
the right edge of the window and is reached by scrolling. The full statement,
with the manual quotation, is in `docs/o1-memory-io-map.md` §2a.

## Sources

- `research/osborne1/2F00153-01_Osborne1TechnicalManual_1982.pdf` §5.0–5.5,
  pp. 23–25 (image-only scan; read by rendering the page range — the manual's
  page 15 is PDF page 29, so the offset is **+14**).
- `tools/romfont.py` — the decoder and the `--glyph-sheet` renderer.
- `docs/o1-rom-variants.md` — the char-gen variants and what differs.
