# bootsplash — draw a boot splash for the Osborne 1, in a browser

A browser tool for designing the **ROM 2.0 boot splash**: a 128×32 grid of the
machine's own characters, as many frames as you like, played back at a chosen
rate, and exported in the format the RP2354B plays (#247's last note).

It is a few files and no server. Open `bootsplash.html` from `file://` — double
click it — and everything works: no build, no network, no install.

| File | What it is |
|---|---|
| `bootsplash.html` | the tool: markup, styles, the UI, and two embedded fonts |
| `core.js` | the glyphs, the frame format and the renderers — no DOM, so it can be tested |
| `decoders.js` | PNG/GIF/BMP readers, for the checks only; nothing in the tool loads it |
| `selftest.js` | checks `core.js` against the repo's own files and tooling |
| `ui-test.js` | drives `bootsplash.html` in a real DOM and checks what it produces |

```sh
node tools/bootsplash/selftest.js     # needs nothing but node and python3
node tools/bootsplash/ui-test.js      # needs jsdom: npm install jsdom
```

`selftest.js` runs 40 checks and `ui-test.js` 46. Neither is wired into CI: the
first needs no dependency and could be, but the second wants jsdom, and this
repo's toolchain has no browser. See "What is checked" for what that buys.

## The screen and the viewport

Two rectangles, and they are not the same one:

- the **screen** is the video buffer: **128 × 32 cells**, 4096 of them, which is
  exactly one 4096-byte window page. That is what a frame *is*, and what the grid
  draws.
- the **viewport** is what the machine actually puts on the glass: **52, 80 or
  104 columns × 24 rows**. Rows 24–31 are never shown, which is why the frame's
  own trailer lives down there.

The three widths are the same physical screen with narrower dots — SCREEN-PAC,
not three machines — so a viewport is the same number of pixels across in every
mode and only the type changes. The viewport is drawn over the grid so a designer
can see what will be visible; **at 52 columns 76 of the 128 columns are off the
screen**, which is easy to spend an hour drawing into.

The overlay's origin is adjustable and its default is **column 0, row 0** —
because that is where the machine actually puts the window. That is worth stating
carefully, because the obvious reading of MAME's driver says otherwise and is
wrong.

`src/mame/osborne/osborne1.cpp` (which `osborne1nx` clones) draws the visible
window as `draw_rows<52, 1>(scroll_x() + 0x0b, …)`, and **`0x0b` is not a window
position**. It is the driver's own note:

> The 7-bit column counter is preloaded near the beginning of the horizontal
> blank period. The initial column is offset by the number of character clock
> periods in the horizontal blank period minus one … there are 12 character
> clock periods in the horizontal blank period, so subtracting 1 gives 0x0B.

**The manual says the same thing independently, in its timing diagram.** *Osborne
1 Technical Manual* §5.8, Figure 5.8A, p. 30: the horizontal period is **64 µs**,
VIDEO begins **12 µs** into it, and the minimum dot duration is **0.125 µs**. So a
line period is `64 / 0.125 = 512` dots = **64 character cells**, of which the 12 µs
before VIDEO is `12 / 0.125 / 8` = **12 cells of horizontal blanking** and the
52 µs of VIDEO is exactly **52 cells** — the 52 columns. (Figure 5.8B does the same
vertically: 260 scan lines in the period, 240 of them VIDEO non-interlaced, which
is the 24 displayed rows of 10 scan lines, leaving 2 rows of blanking.) MAME's
"12 character clock periods" *is* that 12 µs.

The manual gives the **geometry** — §5.1 and §5.2, p. 23: 32 rows of 128
characters in `0F000`–`0FFFF`, "only 24 rows of 52 characters … actually
displayed", a 6821 PIA controlling the display, a 2716 as character generator, a
4116 for the dim bit — but it never says *which* 52 columns. **The origin is not
in the manual.** It is in the ROM, and that is the piece this file got wrong the
first time.

Eleven character clocks, then — and the ROM cancels them exactly. `rom144.asm`
names the constant and writes it at boot:

```
VFLO:	=	-22		;First line video offset
...
;Set beginning line to 0
	DEC	C		;C=0
	CALL	OPBD
;set for -10 char position AND DOUBLE DENSITY
	LDK	C,VFLO
	CALL	OPAD
```

`VFLO = -22` is `0xEA`, port A is `| horizontal offset | DD |`, so the offset
field is **117** — eleven characters, though the ROM's own comment says ten, and
the arithmetic needs eleven: `117 + 11 = 128 ≡ 0 (mod 128)`. The window starts at
buffer column 0. Row 0 is the same story with no bias: the boot writes port B = 0
and MAME reads `m_scroll_y = b_output() & 0x1f`.

So **evaluating `scroll_x() + 0x0b` at `scroll_x == 0` gives 11, and that is a
position the ROM never sets** — it is what the window looks like with its offset
register zeroed, which is not a state the machine is ever in. `DOHOME` in the
same source is the ROM's own "screen at home" routine (`ORI VFLO`), and `AHSCRL`
tests for home with `SUB VFLO` / `RZ`. The **home (0,0)** button puts the viewport
there; the default is already there.

Two footnotes:

- **The SCREEN-PAC lands at column 0 too, by a different route.** Its path is
  `(scroll_x() & 0x60) + (m_hc_left ? 0x09 : 0x01) + 0x17`: it uses only the top
  two bits of the offset — hence the guide's "horizontal scrolling by 32 column
  blocks" — and fills the low five bits with a fixed 1 or 9. With the ROM's 117,
  `(117 & 0x60) + 9 + 0x17 = 128 ≡ 0`. That is also why the stock 52-column mode
  slides a character at a time (`SLIDER` does `LDK C,-2`) while the wide modes
  move in 32-column blocks.
- **80 columns is not a window this machine has at all.** `osborne1nv` is a
  different machine with its own BIOS and character generator, so the 80-column
  setting here is the SCREEN-PAC *dot width*, not a window.

## The pen, and why a capital cannot be typed

Every cell holds a **glyph code, 0–127**, plus one attribute bit. The ROM's own
loader reads art with `sui 65` — subtract 65 from every byte — so:

| Key | Glyph | |
|---|---|---|
| `A`…`Z`, `[`, `\`, `]`, `^`, `_`, `` ` ``, `a` | `0x00`…`0x20` | the graphics set: 33 keys |
| `U+00C0` | `0x7F` | the hatch — no key, so it is clicked from the palette |
| anything else printable | itself | the ordinary letters, digits and punctuation |

That is the ROM's arithmetic, not a convention this tool invented, and it has a
consequence the tool states out loud rather than hiding: **a capital is a glyph
index, not a letter.** Typing `A` with the character pen is refused, with a
message saying which glyph it would have drawn; switch the pen to the graphics
font and it draws that glyph. It is why ROM 2.0's own captions are lowercase
(`research/boot-screen/README.md`).

The **dim/bright** pair is the ninth bit — a separate 4K×1 array that
`OUT (02h)` pages over `F000h`. Bright is `FFh` and dim is `7Fh`, which is what
that array *reads back*: its low seven bits are not physically present and read
high. The tool draws dim at 45% of the ink, so the attribute plane is visible
rather than a number.

## The frame, and the animation container

A frame is **8192 bytes: two 4096-byte halves**, characters then attributes, each
one window page with its own trailer at its own `0FF8h`:

```
half[0000h..0FF7h]  4096 cells, 128 x 32, glyph codes
half[0FF8h..0FFDh]  'O1NEXT', six bytes of magic
half[0FFEh..0FFFh]  the 16-bit sum of the 4088 body bytes, little-endian
```

The contract is `docs/rom-pico-protocol.md` §4 and §5, and **frame *n* of an
export is byte-identical to the committed asset `firmware/rom-service/frame.bin`**
(CRC32 `6eef5af9`). Nothing about the frames is this tool's invention.

The **container** around them is: #247 hands the pacing to the RP2354B, so the
asset becomes a sequence, and a sequence has to say how long each frame lasts.
The header is always written:

```
 0   'O1SPLASH'      8   magic
 8   version u8      1   = 1
 9   flags   u8      1   bit 0 = loop
10   width   u16     2   = 128
12   height  u16     2   = 32
14   fps     u16     2
16   frames  u32     4
20   body    u32     4   = frames * 8192
24   hsum    u16     2   sum of bytes 0..23
26   reserved        6   zero
32   N * 8192            the frames, back to back, each already sealed
```

**This header is a proposal.** The firmware side of #247 is not written, so there
is nothing yet to conform to, and it is one constant to change. What is *not* a
proposal is the 8192 bytes behind it — `tail -c +33 out.bin` is a valid frame
today, and for a one-frame animation it is `frame.bin` exactly.

## Building an animation: copy forward, with an offset

An animation is built by copying a frame forward and moving it. The control takes
a source — **screen** (128×32) or **viewport** (N×24) — and an offset in columns
and rows, and writes it into the next frame, **adding a frame if there is no next
one** (as a copy of the current one, so the animation carries on from where it
was).

The tool is not the device, so there is no reason to move a picture a few cells at
a time, and the offset is not restricted to small or hardware-plausible moves: any
offset, either direction. Three things define the result, and they are the whole
contract:

- **the offset moves the content.** Columns `+4` is four cells right; rows `−2` is
  two rows up.
- **the destination is the same rectangle as the source, and it is cleared first**,
  so content that moves away leaves a blank cell rather than a smear of what used
  to be there.
- **what moves out of the rectangle is clipped, not wrapped.** The video RAM *is* a
  ring buffer, but wrapping a picture is a different operation from moving one, and
  moving one is what this is for.

Underneath it there is a readout, and it is the interesting number:

```
frame 1 → 2: 6 of 4088 cells differ (0.1%), in 2 of 32 rows.
The firmware blits that diff, not the frame; the whole animation is 3 cells
over 2 transitions (worst 2).
```

Because the point of being able to blast whole frames in is that **the firmware
does not have to blit whole frames**. A four-column, two-row move of the screen
*writes* 3716 cells and *differs* by six. The tool writes the rectangle and counts
the diff; **the diffing itself is #247's job, on the Pico.** Nothing in the `.bin`
depends on the readout — it is there so a designer can see what the firmware will
actually be asked to move.

## What is checked

`selftest.js` does not take this tool's word for anything:

- the embedded ROM is `char.ua15` (CRC32 `5297c109`), and every glyph dot decodes
  as `rom[row*128 + code]`, bit 7 leftmost;
- **re-sealing the committed `frame.bin`'s own two halves reproduces it byte for
  byte** — so the trailer is the machine's trailer, not a lookalike;
- a frame built here is **byte-identical** to one built by
  `tools/research/rom2strokes.py` from the same art, through that module's own
  `chars_half`/`attrs_half`/`seal`;
- the committed frame survives `planes → buildFrame` unchanged;
- a bent byte, a bent magic and a truncated container are each caught;
- the **copy-forward shift** is checked as a contract: a shift of (0,0) is the
  identity, a move writes the whole rectangle it can and leaves a blank where the
  content was, a shift far enough to clip still clears what it vacates, a viewport
  blit touches nothing outside the viewport, and the trailer's cells are never read
  or written — while the *diff* for the same move is a handful of cells, which is
  the number that matters;
- the PNG decodes back to the pixels that went in under **both** deflate paths
  (stored blocks and zlib), and `sips` agrees it is that size;
- the GIF decodes back to the frames that went in under **two independent
  readers**: this repo's own LZW reader, written to the spec, *and* macOS's
  ImageIO, asked through `sips -s format bmp`. That second one is what found the
  encoder's first bug — a dictionary seeded with single-pixel codes, which made
  the encoder swallow the second pixel of every run.

`ui-test.js` loads `bootsplash.html` into a real DOM (jsdom, with the canvas
stubbed to record rather than rasterise) and then drives it the way a person
does: click a cell and type, click a palette swatch, add, copy and delete frames,
and press each of the four download buttons — then decode what came out of them.

Two things neither covers: the page in a real browser (no headless browser is
installed on this machine), and MAME. A frame that validates and whose bytes
match `rom2strokes.py`'s has not yet been *seen* on the emulated machine — that
is `bootscreen-check.sh`'s job, and #247's.

## Provenance of the embedded blobs

| Embedded | From | CRC32 |
|---|---|---|
| the 128 glyphs, in `core.js` | `tools/emulator-setup/roms/char.ua15` | `5297c109` |
| `Osborne1 80`, in `bootsplash.html` | `site/assets/fonts/osborne1-80.woff2` | `29eafd63` |
| `Osborne1 Art 80` | `site/assets/fonts/osborne1-art-80.woff2` | `f09dbd26` |

The two faces are copies of files `tools/romfont.py` builds from that same ROM
and verifies against it; they are used for the chrome and for the art-text panel.
**The grid, the palette, the preview, the PNG and the GIF are all drawn from the
ROM's own bits**, so what is on the screen is what the machine would draw — and
the tool asserts the ROM's CRC32 at load and prints it in the page.

## Known boundaries

- **`rom2strokes.py`'s art loader has no `U+00C0` case.** Its `chars_half`
  handles the graphics range and the printable range, so a cell holding the
  `0x7F` hatch is expressible in a `.bin` and in this tool's own text round trip,
  but *not* through that tool's `--art`. `selftest.js` asserts the difference
  rather than papering over it. One line in that tool would close it.
- **Art text cannot express a cell holding glyph `0x41`–`0x61`**, because those
  characters *are* the graphics keys. Only a foreign `.bin` can put one there —
  no pen in this tool can — and the exporter reports how many cells would be lost
  rather than exporting them silently.
- **`rom2strokes.py --art` cannot be pointed at a 128-column screen at all**: its
  CLI runs a stripe proof first that indexes the 153-column boot-screen art's
  letter boxes. The self-test imports the module and calls the functions it
  needs, which is the same code the CLI would have run.
- **A GIF cannot encode a delay below 2 hundredths of a second**, and browsers
  often clamp playback under 20 ms, so a GIF of a 60 fps animation plays slower
  than the machine will. The `.bin` is not affected.
- **The page is untested in a real browser** on this machine. The DOM test covers
  the logic; layout and canvas rendering are checked by eye.

## Related

- **#247** — the boot screen, and the animation this feeds.
- `docs/rom-pico-protocol.md` — the frame contract (§4.1, §5) and the trailer (§6).
- `docs/o1-rom-2.0.md` §4.9 — the screen, and why one page is exactly one screen.
- `research/boot-screen/` — the authored art, and the `sui 65` convention.
- `tools/romfont.py` — the fonts this tool embeds, and the graphics-set sheet.
- `tools/research/rom2strokes.py` — the repo's own frame builder, which the
  self-test compares against.
