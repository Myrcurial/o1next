# rom-service — the ROM's window page 1, and the boot frame in flash

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, and the boot
screen compiled into the RP2354's own flash — **one frame, or a sequence of them**.
The contract is `docs/rom-pico-protocol.md` (#247 step 8); this directory holds the
frame and the animation that contract names.

| File | What it is |
|---|---|
| `frame.bin` | the boot frame: **8192 bytes = two 4096-byte halves**, characters then attributes, each carrying its own `O1NEXT` magic and 16-bit sum at its own `0FF8h`. A **generated, committed** artifact — regenerate it with the command below and never hand-edit it |
| `bootsplash.bin` | the boot screen as an **animation**: a 32-byte `O1SPLASH` header and then **90 sealed frames** back to back, 8 fps, played once. Every frame is the same 8192-byte two-half artifact as `frame.bin`, with its own art. SHA-256 `0d9fa6c2…42541b` — see "The animation" below |

Regenerate, from the repo root:

```sh
tools/research/rom2strokes.py --frame firmware/rom-service/frame.bin
```

`tools/research/rom2strokes.py --check` re-builds it from
`research/boot-screen/o1next-art.txt` and compares bytes, so the art and the
asset cannot drift; `.github/workflows/generated-artifacts.yml` runs that on
every change to either.

## Why two halves

The O1's video cell is **nine bits** — eight of character and one of brightness —
and the ninth is not in the video RAM: it is a separate 4K×1 array that
`OUT (02h)` pages into `F000–FFFF`, with its low seven bits reading high because
they are not physically present. So the frame is two window pages, served one at
a time by `PRESENT(1)` and `PRESENT(2)`, and **each half validates itself** —
either can be checked without the other, and the trailer *is* the "is a frame
there?" query, so missing, erased and corrupt are one case.

v1.0's attribute half is all `FFh` — every cell bright — because bit 7 set is
bright and `FFh` is what the array reads back. That is a frame, not a limit of
the format: the ROM blits the attribute half whenever it validates, so a later
frame can carry dim accents with **no ROM change**.

Both halves are the *character* half's shape: the trailer's eight bytes sit in
cells 4088–4095, which are row 31, and rows 24–31 are off-screen on the machine.

## The animation

`bootsplash.bin` is the boot screen as a **sequence**: a 32-byte `O1SPLASH` header
and then 90 sealed frames back to back, 737,312 bytes in all. The header says
128 × 32, **8 fps**, **flags 0 — `once`**, and carries its own 16-bit sum over bytes
0–23, so the container validates itself before a frame is read. Each frame is the
same 8192-byte two-half artifact as `frame.bin`, and each half carries its own
`O1NEXT` trailer, so all 90 frames pass the machine's own test.

The header says 128 × 32, **8 fps**, and **flags 0** — which the container's own
specification reads as **`once`**: play the sequence through, and stop on the last
frame. The flags byte is two independent bits (bit 0 repeat, bit 1 bounce), so the
four modes it can express are `once` (0), `loop` (1), ping-pong once (2) and
ping-pong repeat (3); this asset uses the first, and **#269** is where the container
and all four modes are specified.

**It is not `frame.bin`'s art, and nothing here regenerates it.** `frame.bin` is
built by `rom2strokes.py --frame` from `research/boot-screen/o1next-art.txt`; the
animation is a separate, hand-drawn piece whose source is the designer tool, so
`rom2strokes.py --check` has nothing to compare it against. What *is* checked is
that it is the format it claims to be: all 90 trailers hold, the header sum holds,
and re-building the file from its own parsed frames reproduces it **byte for byte**.

| | |
|---|---|
| exported from | `tools/bootsplash/bootsplash.html`, 2026-10-16 |
| frames | 90 at 8 fps — 11.25 s, played `once`, resting on the last frame |
| SHA-256 | `0d9fa6c207517156e6230e8c10e625d1870daa0e4225d563290d0d1edf42541b` |
| what it plays | the striped `O` mark and its two captions; a full-buffer `O1NEXT` wipe; a clear; the mark rising into place; then `press return to begin`, whose **return** blinks bright and settles |
| where the ink is | the settled frames stay inside **columns 0–50**, so they fit the 52-column window; the wipe phase runs to the buffer's own edge (column 127), so a 52-column window sees only its left half |

**The art text is not the source, but it could be.** Every frame is expressible in
the repo's art-text convention — the big wordmark is drawn with the *block* glyphs
(`0x08`, `0x0A`, `0x15`, `0x16`, `0x18`, `0x19`) rather than letters, and the
captions are lowercase — so **no cell holds a glyph in `0x41–0x61`**, which is the
art-text format's one lossy range. The tool exports a frame as art text one frame at
a time; 90 of those files plus `rom2strokes.py --frame` would make this asset
regenerable the way `frame.bin` is. Nobody has asked for that yet, so the `.bin` is
the artifact of record and this paragraph is the note that the path exists.

## What is not here yet

- the C module: `PRESENT`, the two doors (`0E7h`/`0EBh` for userland, bank-2
  `2300h`/`2301h` for the ROM), the frame served out of flash
- the ROM's screen code and the `softrom_device` selector — #247's turns 1–4,
  which prove the sequence in the emulator first
- **how the ROM asks for frame *n*.** `PRESENT(1)` and `PRESENT(2)` name the two
  halves of *the* frame; a sequence needs the door to name which one, or the
  firmware to advance its own sequence and serve "the frame" as it does today.
  That is #247's open question, and committing this asset does not answer it
