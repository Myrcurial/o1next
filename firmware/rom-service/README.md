# rom-service — the boot screen in the RP2354B's flash, and the ROM's window page 1

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, the **boot
screen** compiled into the RP2354B's own flash, and the ROM-side assets the
monitor's stub asks for. The contract is `docs/rom-pico-protocol.md` (#247 step
8); **#247's W5** is where the interaction itself was regenerated, and "How the
screen gets drawn" below is the summary.

| File | What it is |
|---|---|
| `boot-animation.bin` | **the boot screen**: a 32-byte `O1SPLASH` header and then **90 sealed frames** back to back, 8 fps, played once. Each frame is **8192 bytes = two 4096-byte halves**, characters then attributes, each carrying its own `O1NEXT` magic and 16-bit sum at its own `0FF8h`. SHA-256 `0d9fa6c2…42541b` — see "The animation" below |
| `screen.bin` | the boot screen's **code**: 4096 bytes, the window page the monitor's stub asks for with `PRESENT(3)` and copies to RAM at `4000h`. The code is the first 183 bytes; the rest is the vendor's own `FFh` fill; and the top of the page carries a trailer the code never reads — `O1NEXT`, the digest of the source it came from, and a 16-bit sum. Also **generated and committed** |

**The animation is not generated here, and nothing re-checks it against a source.**
The tool that drew it is interactive — `tools/bootsplash/` *is* the tool — so there
is no art file to re-render it from. What is checked is that the file is the format
it claims to be, and that is checked against the machine's own trailer test.
`frame.bin`, the two-half boot frame that used to sit here, was **retired on
2026-10-16** when the boot screen became the animation the RP2354B plays.

## The frame, and why it is two halves

A frame here is the O1's video cell made portable. The cell is **nine bits** — eight
of character and one of brightness — and the ninth is not in the video RAM: it is a
separate 4K×1 array that `OUT (02h)` pages into `F000–FFFF`, with its low seven bits
reading high because they are not physically present. So a frame is **two 4096-byte
halves**, characters then attributes, and **each half validates itself**: the
trailer *is* the "is a frame there?" query, so missing, erased and corrupt are one
case.

Regenerate the blob, which needs a build — the vendor's ACT80 is what makes its
bytes:

```sh
tools/research/rom2asm.sh -o /tmp/rom2-monitor.rom \
                          -b firmware/rom-service/screen.bin
```

`tools/research/rom2blob.py --check` **cannot** rebuild it: CI has no MAME, and no
amount of Python recomputes the ACT80's output. So its guard is a staleness check
instead — `screen.bin` records the digest of the source it was extracted from, and
the check fails when that source has moved on without it. That is the half that
can be checked anywhere. The other half is `rom2asm.sh`'s own step 7, which checks
that the blob's records and the assembler's `Program LWA` agree.

`.github/workflows/generated-artifacts.yml` runs both `--check`s on every change to
either source or either asset.

The **9th bit is used**. The old v1.0 frame was all-bright (`FFh` in every attribute
cell, which is what the array reads back), but the animation carries real **dim
accents** — between 164 and 1440 cells a frame, depending on where it is — which is
exactly the case the format was kept for: dim needs no ROM change, because the ROM
blits the attribute half whenever it validates.

Both halves are the *character* half's shape: the trailer's eight bytes sit in cells
4088–4095, which are row 31, and rows 24–31 are off-screen on the machine.

## The animation

`boot-animation.bin` is the boot screen as a **sequence**: a 32-byte `O1SPLASH` header
and then 90 sealed frames back to back, 737,312 bytes in all. The header says
128 × 32, **8 fps**, **flags 0 — `once`**, and carries its own 16-bit sum over bytes
0–23, so the container validates itself before a frame is read.

The flags byte is two independent bits (bit 0 repeat, bit 1 bounce), so the four
modes it can express are `once` (0), `loop` (1), ping-pong once (2) and ping-pong
repeat (3). This asset uses the first, which is what a boot screen wants: the last
frame is the resting prompt, so the sequence plays through and stays there. The
container and all four modes are specified in `docs/rom-pico-protocol.md` §5.1.

| | |
|---|---|
| exported from | `tools/bootsplash/bootsplash.html`, 2026-10-16 |
| frames | 90 at 8 fps — 11.25 s, played `once`, resting on the last frame |
| SHA-256 | `0d9fa6c207517156e6230e8c10e625d1870daa0e4225d563290d0d1edf42541b` |
| what it plays | the striped `O` mark and its two captions; a full-buffer `O1NEXT` wipe; a clear; the mark rising into place; then `press return to begin`, whose **return** blinks bright and settles |
| where the ink is | the settled frames stay inside **columns 0–50**, so they fit the 52-column window; the wipe phase runs to the buffer's own edge (column 127), so a 52-column window sees only its left half |

**The art text is not the source, and is not wanted as one.** The tool that drew it
is interactive, so the `.bin` is the artifact of record and nothing in this repo
rebuilds it. (For the record, it *would* survive a round trip through the art-text
convention — the wordmark is drawn with block glyphs and the captions are lowercase,
so no cell holds a glyph in `0x41–0x61` — but that is a fact, not a plan.)

## How the screen gets drawn (#247's W5)

**The RP2354B is the display.** It snoops the Z80's video RAM into a shadow and
draws the screen itself — the animation included, paced from its own clock and its
own flash — and it **stops on the Z80's first video-RAM write**, which every boot
path makes within milliseconds. The Z80's whole role becomes the trigger: the
monitor's stub asks once and returns, and the guest never has to decide anything.

That is what retires the guest-side machinery for the splash — the 4096-byte blob,
`PRESENT(3)` as a page, and the two-half frame serving — and it is a *shape change*
to step 8 rather than a tweak. It is specified in #247 (W5); retiring that machinery
is that branch's work, not this asset's.

## What was retired, and when

`frame.bin` — the single 8192-byte frame built by `tools/research/rom2strokes.py
--frame` from `research/boot-screen/o1next-art.txt`, and re-checked byte for byte by
`--check` in CI — was **removed on 2026-10-16**. The animation supersedes it: W5
makes the frame asset *the animation the RP2354B plays*, and retires the two-half
serving with it. The generator and the check went with the asset, so nothing in the
repo rebuilds a single frame from that art any more.

Two consequences, both deliberate:

- **`research/boot-screen/` stays.** Its art is no longer the boot screen, but it is
  still the **site masthead's** source (`site/assets/o1next-logo.png`, via `--logo`),
  and that is the half of `--check` that remains.
- **The MAME harnesses still mount a frame.** `romservice-check.sh` asks for
  `firmware/rom-service/frame.bin` and now stops immediately with *"no boot frame
  at …"*. That directory is rewritten by the #247 branch — the frame slot, the
  screen's code, the four acceptances — so it was left to that work rather than
  patched twice here.

## What is not here yet

- the C module: `PRESENT`, the two doors (`0E7h`/`0EBh` for userland, bank-2
  `2800h`/`2801h` for the ROM — *not* `2300h`/`2301h`, which is the floppy's
  track register and the keyboard's row 0; `docs/rom-pico-protocol.md` 2), the
  payload served out of flash
- `PRESENT(3)` in `softrom_device` and the screen harness — #247's turns 4 and 5,
  which prove the sequence in the emulator first. The screen's code is written and
  assembles (`research/source-code/BIOS-200-source/rom2-screen.asm`), and
  `screen.bin` is extracted from that build; what is missing is the device slot
  that serves it and the check that reads the video RAM back.
- the RP2354B's own video renderer: the shadow VRAM, the frame pacing, and the stop
  on the Z80's first write — W4 and W5 of #247, which prove it in the emulator first
- the retirement itself: the blob, `PRESENT(3)` and the two-half serving are still
  in the tree on the #247 branch
