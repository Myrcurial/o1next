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

`selftest.js` runs 89 checks and `ui-test.js` 140. Neither is wired into CI: the
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

### Zoom, and why the grid is shown at its own size

**Zoom is a real change in size, not only in resolution.** The grid is displayed at
one CSS pixel per dot times the zoom step — 666 px wide at 80 columns and 1×, 1331
at 2× — and the panel scrolls when that is wider than the column. The canvas's
backing store is drawn at device-pixel resolution so it stays crisp on a retina
display, and exports use the zoom's dot scale rather than the display's.

This was wrong for a while and it is worth knowing why, because the symptom was
odd: the canvas had `width: 100%` in CSS, so it was stretched to its column at
*every* zoom and the only thing a zoom step changed was the number of pixels behind
the stretch. Nothing moved on screen. The fix was to stop stretching it, and to put
the overlay layer in a box the size of the canvas (`.screenbox`) so the viewport and
cursor marks still line up — including when the panel is scrolled.

**1× is the default**, because at 80 columns that is the whole screen in a normal
window. The preview is the exception: it is scaled to fit its box, since it is for
watching the animation rather than for inspecting pixels.

**The area beside a canvas narrower than its panel is the panel.** At 1× in a wide
window there can be a lot of it, and it is the machine's blue-grey (`--panel`,
`#687898`, the same colour the border already was) with the canvas inset 6 px — so
the screen reads as mounted in the front panel. It was `#000`, which is a hole: black
beside the black the canvas itself draws. The page's own background is not the answer
either, being *darker* than the box it would sit in, which is a hole of another shade.

## The pen: the whole ROM, always

Every cell holds a **glyph code, 0–127**, plus one attribute bit. That is all a
cell is: the character generator is indexed with `chr & 0x7f` — MAME's driver is
`m_p_chargen[(ra << 7) | (chr & 0x7f)]` — so **all 128 glyphs can go in any cell**.
There is no hardware subset, and nothing about a frame restricts you to the
letters.

The `sui 65` arithmetic that `research/boot-screen/` is built on is a property of
the **art-text authoring format**, not of the frame: the ROM's *loader* subtracts
65 from every byte of a text file, so that ASCII letters index the block glyphs.
This tool writes frames directly and there is no assembler anywhere in the path, so
it does not inherit that restriction. It took a correction to get there — the
first version of this tool did inherit it, and made capitals unreachable and made
the graphics pen refuse most keys. The pen is now:

| Setting | What a key means |
|---|---|
| **Standard characters** (the default) | the key's own code *is* the glyph. `A` draws a capital A, `p` draws a p, space draws the blank — every printable character, `0x20`–`0x7E`. |
| **Graphical characters** | the ROM's `sui 65` loader arithmetic, kept for one purpose: a screen authored this way is one whose `.txt` export `rom2strokes.py` can read back. `0x41`–`0x61` become glyphs `0x00`–`0x20`, so in *this* mode a capital cannot be typed as a letter. |

**Neither mode refuses a key, and the palette shows only what the mode can place.**

| Pen mode | The palette shows | Labelled with |
|---|---|---|
| **Standard characters** | the **95** printable glyphs, `0x20`–`0x7E` | the character you type |
| **Graphical characters** | the **34** graphical cells: the 32 blocks `0x00`–`0x1F`, the blank, and the `0x7F` hatch | the `sui 65` key that reaches it — `A`…`` ` ``, `a`, and `U+00C0` for the hatch |

Between them the two sets cover **all 128 glyphs** of the character ROM — `0x20` is in
both, because the space bar types the blank in either mode — so everything is still
reachable, one mode switch away. **Every swatch in a set has a key in that mode**, so
the palette doubles as the key map, and the tooltip says what the *other* mode would
need (including "no key", which is the question worth answering). Clicking a swatch
makes it the pen; clicking it again clears it.

**A cell click only aims the cursor.** It places nothing unless you tick **paint
cells on click** under the palette — because a click that also painted *and advanced*
would put your next keystroke one cell to the right of where you clicked, which is
not how anyone uses a keyboard. With a glyph as the pen, **fill with pen** paints it
over a selection.

The cost of standard characters falls entirely on the `.txt` export: art text cannot carry
a cell holding glyph `0x41`–`0x61`, because those characters *are* the graphics
keys. The exporter counts them and says so rather than writing something that will
read back wrong, and **the `.bin` is unaffected** — a frame is glyph codes and has
no such limit.

The **dim/bright** pair is the ninth bit — a separate 4K×1 array that
`OUT (02h)` pages over `F000h`. Bright is `FFh` and dim is `7Fh`, which is what
that array *reads back*: its low seven bits are not physically present and read
high. The tool draws dim at 45% of the ink, so the attribute plane is visible
rather than a number.

## The selection, the clipboard, and the ninth bit

Drag on the grid to make a rectangle. With nothing selected, every one of these
actions applies to the single cell under the cursor — which is why they are all
usable without a selection, and why the hint above them says which it is.

| | |
|---|---|
| **copy**, **cut**, **paste** | `Ctrl`/`Cmd`-`C`, `-X`, `-V`, or the buttons. Paste puts the block down with its top-left corner at the cursor, clipped to the screen. |
| **toggle dim/bright** | `Tab`, or the button. **Flips the ninth bit and leaves the glyph exactly where it is** — changing how bright a cell is never needs the character entered again. |
| **fill with pen**, **blank**, **dim**, **bright** | the rest of the block operations. |

The clipboard holds **both planes** — the glyph *and* the ninth bit — so it is
deliberately not art text: art text is the *file* format and cannot carry glyphs
`0x41`–`0x61` or the attribute bit at all. `.txt` export/import is how a selection
travels *between* tools; this is how one travels within the tool, exactly.

## The frame, and the animation container

A frame is **8192 bytes: two 4096-byte halves**, characters then attributes, each
one window page with its own trailer at its own `0FF8h`:

```
half[0000h..0FF7h]  4096 cells, 128 x 32, glyph codes
half[0FF8h..0FFDh]  'O1NEXT', six bytes of magic
half[0FFEh..0FFFh]  the 16-bit sum of the 4088 body bytes, little-endian
```

The contract is `docs/rom-pico-protocol.md` §4 and §5, and **the committed asset
is this tool's own output**: `firmware/rom-service/boot-animation.bin`, the 90-frame
animation. Nothing about the *frames* is this tool's invention — the format is the
machine's, and what it writes is what ships.

The **container** around them is: #247 hands the pacing to the RP2354B, so the
asset becomes a sequence, and a sequence has to say how long each frame lasts.
The header is always written:

```
 0   'O1SPLASH'      8   magic
 8   version u8      1   = 1
 9   flags   u8      1   bit 0 = loop, bit 1 = ping-pong
10   width   u16     2   = 128
12   height  u16     2   = 32
14   fps     u16     2
16   frames  u32     4
20   body    u32     4   = frames * 8192
24   hsum    u16     2   sum of bytes 0..23
26   reserved        6   zero
32   N * 8192            the frames, back to back, each already sealed
```

**This header is the firmware's contract now**, not a proposal: #247's W5 makes the
frame asset *the animation the RP2354B plays*, the RP2354B paces it from its own
flash and stops on the Z80's first video-RAM write, and
`firmware/rom-service/boot-animation.bin` is the first instance of it. What is *not*
this tool's invention is the 8192 bytes behind the header — `tail -c +33 out.bin` is
a valid frame. The flags byte, and what each mode plays, is
`docs/rom-pico-protocol.md` §5.1.

## The playback mode: the four things two bits can say

All four are offered, and they are the header's two flag bits rather than one:

| mode | flags | what it plays |
|---|---|---|
| **once** | 0 | `1 2 3` — forward, and stop on the last frame |
| **loop** | 1 | `1 2 3 1 2 3 …` — forward, then back to the first frame |
| **ping-pong, once** | 2 | `1 2 3 2 1` — the bounce, back to the first frame, and stop |
| **ping-pong, repeat** | 3 | `1 2 3 2 1 2 3 2 …` — the bounce, forever |

The two bits are independent because they answer two different questions, and a
reader can test either one alone: **bit 0, does it repeat at all** and **bit 1, does
it reverse at the ends instead of jumping**. So flags 2 is not a mistake to be
normalised away — it is "bounce once and stop", and it is a mode like any other.
`buildAnimation` still takes a boolean, which is what this container had before
ping-pong existed: `true` is `loop`.

**A bounce does not play the ends twice.** Three frames bounce as `1 2 3 2 1 …`: the
last frame is *turned on* once and reversed from, so a repeating bounce is `2n − 2`
frames a cycle. A bounce also **ends where it started**, and that is the one thing
the two ping-pongs do differently — the one-shot plays the return to frame 1 and
stops there (`2n − 1` frames), while the repeating one leaves that return to the wrap
into the next cycle. Which is why the preview timer, the GIF's loop flag and the diff
all ask one question, `modeRepeats`, rather than "is the mode `once`": **a one-shot
bounce stops too**.

The preview, the GIF and the diff read the order from one place in `core.js`
(`playbackOrder`), so the tool cannot disagree with itself about what a mode plays.
The GIF writes the bounce out in full rather than handing a forward pass to the
viewer's own looping, because the GIF is a preview of what the machine plays — and a
one-shot bounce's GIF does not repeat, so it stops where the machine stops.

And the mode changes the **diff readout**, which is the number that matters: a bounce
has to blit the way back as well, which is the forward transitions again in reverse
and so exactly twice the forward cost, and a loop has one transition a once-through
does not — last → first. Both ping-pongs cost the same, because the one-shot's last
blit is the return to frame 1 and the repeating one's is the wrap into the next
cycle: the same transition, taken once either way. Reading "3 cells over 2
transitions" while the machine plays a six-step bounce was reading the wrong number.

## Re-ordering the frames

The frame list *is* the animation, so re-ordering is an edit and not a view:

| | |
|---|---|
| **move ◀ / ▶**, `Alt`+`←`/`→` | move the frame you are on one position earlier or later. The cursor follows the frame it moved, because that is the frame you were working on. |
| **drag a thumbnail** | drop it where it belongs. The strip is the play order. |
| **copy to position** | a copy that lands *at* a position rather than immediately after its source: with twelve frames, frame 11 copied to 13 makes the copy frame 13, and whatever was there moves along. |

All three call one function, because three ways of moving a frame that disagree
would be three ways to lose work. The drag is deliberately written to work without
a `DataTransfer` — jsdom has none, and a drag that only works when the browser
supplies one is a drag that cannot be tested.

## Importing: the whole animation, or the frame you are on

A file is read for what it is — art text, a bare 8192-byte frame, or a container of
one or more frames — and then **placed**, which is the choice:

| Into | What it does |
|---|---|
| **the whole animation** | what you import replaces everything, its fps and its playback mode included. This is what import has always done. |
| **this frame** | the file's frames are written in *starting at the frame you are on*. What is there is replaced, the animation grows if the file is longer, and nothing before that frame is touched. The file's own fps and playback mode are ignored, because you are importing into an animation rather than replacing it. |

**Into this frame** is how a half-built animation gets added to, and it is the
reason the tool can be closed and reopened mid-job: export the twelve frames you
have, keep the `.bin`, draw frame thirteen somewhere else, and drop it in — no
re-drawing, and nothing to re-order afterwards.

**A one-frame `.bin` is either shape and both are accepted**: 8192 bytes on their
own, or those same bytes behind the 32-byte header, because both are what this tool
writes for a one-frame animation. A container of several frames imported into a
frame grows the animation by however many do not fit, and the status line says how
many were replaced and how many were added rather than leaving you to count.

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
- **every frame of the committed animation passes the machine's own trailer test**,
  and **re-sealing frame 1's two halves reproduces it byte for byte** — so the
  trailer is the machine's trailer, not a lookalike;
- a frame built here is **byte-identical** to one built by
  `tools/research/rom2strokes.py` from the same art, through that module's own
  `chars_half`/`attrs_half`/`seal`;
- the committed frame survives `planes → buildFrame` unchanged;
- a bent byte, a bent magic and a truncated container are each caught;
- the **playback mode** is checked as a bitfield and as a behaviour: all four flags
  bytes parse, each is its own mode, the two bits are reported separately, a boolean
  still means what it meant before ping-pong existed, an unknown mode word is refused
  rather than written as something else, and `playbackOrder` gives what each mode
  plays — `123`, `12321` and `1232` for three frames, the two-frame bounce, and the
  one-frame case. `modeRepeats` is checked as bit 0, which is the question the timer
  and the GIF's loop flag have to ask, because a one-shot bounce stops too. The
  **diff** is checked per mode: a loop adds the wrap as a transition, a bounce is the
  forward pass twice over, both ping-pongs cost the same, and an older caller that
  passes no mode counts what it counted before;
- the **pen** is checked as a claim about the machine rather than a convention:
  every printable key reaches a glyph in *both* modes, standard characters give the
  key's own code (`A` → `0x41`), graphical characters give the loader's arithmetic
  (`A` → `0x00`), and **all 128 glyphs are reachable** — by a key, or from the palette;
- the **palette sets** are checked as a partition: standard offers the 95 printable
  glyphs and no blocks, graphical offers the 34 blocks and the hatch, the two together
  cover all 128, and every swatch in a set has a key in that mode — so the palette is
  also the key map. And a **cell click is checked not to paint** unless paint-on-click
  is ticked, since a click that painted *and* advanced is what made click-then-type
  land a cell to the right;
- the **zoom** is checked to change the displayed size and not only the backing
  store — which is the bug it had: a canvas stretched to its column renders every
  zoom step as the same picture;
- the **clipboard** is checked for the thing it must not lose: a copy of a cell
  holding glyph `0x41` *and* dim keeps both, paste puts both down and clips at the
  screen edge and the trailer, and `invertAttrs` flips the ninth bit twice to the
  identity with the glyph untouched;
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
does: click a cell and type, click a palette swatch, add, copy, re-order and
delete frames, drag a thumbnail, import a file into the animation *and* into a
frame, press each of the four download buttons, and press play — then decode what
came out of them. The playback is watched, not assumed: with five frames in
ping-pong the test collects the frame numbers the preview actually walks and
requires that it reaches 5 and then goes *down*; in ping-pong-once it requires the
walk to be exactly `1 2 3 4 5 4 3 2 1` and the timer to stop on frame 1; and in
`once` it requires the timer to stop itself on the last frame.

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
  characters *are* the graphics keys. With standard characters that is one keystroke away —
  type a capital — so the exporter reports how many cells would be lost rather than
  writing characters that read back as different glyphs. The `.bin` carries them
  fine; this is a limit of the art-text format, not of the frame.
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
