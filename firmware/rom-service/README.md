# rom-service — the ROM's window, the door, and the boot screen the RP2354B plays

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, and the **boot
screen** compiled into the RP2354B's own flash. The contract is
`docs/rom-pico-protocol.md` (#247 step 8); **#278** is where the ROM-side frame path
was retired, and "How the screen gets drawn" below is the summary.

| File | What it is |
|---|---|
| `boot-animation.bin` | **the boot screen**: a 32-byte `O1SPLASH` header and then **90 sealed frames** back to back, 8 fps, played once. Each frame is **8192 bytes = two 4096-byte halves**, characters then attributes, each carrying its own `O1NEXT` magic and 16-bit sum at its own `0FF8h`. SHA-256 `0d9fa6c2…42541b` — see "The animation" below |

**That is the only asset, and nothing is generated here.** The tool that drew the
animation is interactive — `tools/bootsplash/` *is* the tool — so there is no art
file to re-render it from. What is checked is that the file is the format it claims
to be, and that is checked against the machine's own trailer test
(`tools/research/bootanim.py --check`). Two assets that used to sit here are gone:

- `frame.bin`, the two-half boot frame, **retired on 2026-10-16** when the boot
  screen became the animation the RP2354B plays;
- `screen.bin`, the screen's **code**, which was served to the ROM as a window page
  and guarded by `tools/research/rom2blob.py --check` — **retired on 2026-10-17
  (#278)** with the ROM-side frame path, when the code came back into the monitor's
  own tail where it fits (26 bytes). The tool went with it.

## The frame, and why it is two halves

A frame here is the O1's video cell made portable. The cell is **nine bits** — eight
of character and one of brightness — and the ninth is not in the video RAM: it is a
separate 4K×1 array that `OUT (02h)` pages into `F000–FFFF`, with its low seven bits
reading high because they are not physically present. So a frame is **two 4096-byte
halves**, characters then attributes, and **each half validates itself**: the
trailer *is* the "is a frame there?" query, so missing, erased and corrupt are one
case.

**The format did not change when the ROM's path to it did (#278).** The RP2354B is
what reads a frame now — out of this animation, in its own flash — and the ROM never
sees one: the Z80's whole role is the trigger, and the trigger is the fallback text
the monitor's own screen code prints. So the trailer, the two halves and the 9th bit
are all still exactly what they were; what retired is the ROM asking for a frame
through the door.

The **9th bit is used**. The old v1.0 frame was all-bright (`FFh` in every attribute
cell, which is what the array reads back), but the animation carries real **dim
accents** — between 164 and 1440 cells a frame, depending on where it is — which is
exactly the case the format was kept for.

Both halves are the *character* half's shape: the trailer's eight bytes sit in cells
4088–4095, which are row 31, and rows 24–31 are off-screen on the O1's 24-row
display. That is deliberate — a frame's trailer is never visible.

## The animation

| | |
|---|---|
| container | `tools/bootsplash/README.md`; reader and validator: `tools/research/bootanim.py` |
| header | 32 bytes: `O1SPLASH`, version, flags, 128 × 32, fps, frames, body length, header sum |
| flags | bit 0 `LOOP`, bit 1 `PINGPONG` — `once` here, so it plays through and stops on frame 89 |
| pacing | 8 fps, from the RP2354B's own clock |
| frames | 90 × 8192 bytes = 737280, plus the 32-byte header |
| validation | `python3 tools/research/bootanim.py --check` — the container's sum, its geometry and flags, and every frame's own trailer |

**The animation is the RP2354B's to draw and the ROM's to *trigger*.** Nothing on the
ROM side looks at its content, and nothing serves it: the Z80 prints the fallback,
the RP2354B notices, and the rest is the Pico's.

## How the screen gets drawn (#247's W5, and #278)

**The RP2354B is the display.** It snoops the Z80's video RAM into a shadow and
draws the screen itself — the animation included, paced from its own clock and its
own flash — and it **stops on the Z80's first video-RAM write**, which every boot
path makes within milliseconds. The Z80's whole role is the **trigger**: the monitor
prints the fallback (its own two lines, at the animation's own rows and columns,
with its own bright/dim runs) and returns to the sign-on prompt, and the guest never
has to decide anything.

**And the Z80 draws nothing else (#278).** The monitor used to ask the interposer for
the screen's *code* (`PRESENT(3)`), copy it to RAM at `4000h` and run it, because 212
bytes did not fit the 72 the vendor's guard left free. The frame path's retirement
removed the bulk of that code — the two trailer checks and the two `LDIR` blits were
most of it — so what is left is **26 bytes of fill, print and return**, and it lives
in the monitor's own tail: `0F67h`–`0FCDh`, 103 bytes of the tail's 149, **46 free**
to the guard at `0FFBh` (it was 21). `research/source-code/BIOS-200-source/` is the
record, and `tools/research/rom2asm.sh` is the build.

**The message moved into the vendor's own sign-on slot.** `IMSG` at `019Fh` was 182
bytes of the stock message, and the sign-on dispatch no longer prints it: ROM 2.0's
72-byte fallback lives there now, with the vendor's `FF` fill behind it, because the
slot's *length* is what anchors everything below `0F67h` — the CBIOS calls ROM
routines by absolute address (`docs/o1-rom-2.0.md` §4.2), and there is no `ORG`
between `IMSG` and the tail to absorb a shorter one. The 110 bytes left over are what
§4.7's signature and extension table will take.

## What the ROM service still answers

- **`PRESENT(0)`** — the payload (CBIOS + MD-10 BIOS + the hand-over stub), which is
  where window page 1 already is. **The one content id left**: `1` and `2` (the
  frame's halves) and `3` (the screen's code) retired with the frame path (#278) and
  answer `09h`, leaving page 1 alone.
- **`INFO`** — the version and a flags byte that is now always `00h`: there is no
  asset slot left to report. It stays in the reply because the reply's *shape* is
  the protocol's.
- **`ECHO`**, **`NOP`** and the abandon-a-pending-reply rule — unchanged.

The ROM asks the interposer for **nothing** at the sign-on now: the payload is
already in page 1, put there by the softROM itself, so there is nothing to restore.
The door's remaining clients are the userland one (I/O `0E7h`/`0EBh`, for `MOUNT.COM`
and the clock publisher) and the web UI's `INFO`.

## What is not here yet

- the C module: `PRESENT`, the two doors (`0E7h`/`0EBh` for userland, bank-2
  `2800h`/`2801h` for the ROM — *not* `2300h`/`2301h`, which is the floppy's
  track register and the keyboard's row 0; `docs/rom-pico-protocol.md` 2), the
  payload served out of flash
- the RP2354B's own video renderer: the shadow VRAM, the frame pacing, and the stop
  on the Z80's first write — #277, which is gated on PicoEm (#192) and proves it in
  the emulator first. What it draws is `boot-animation.bin`, and
  `tools/research/bootanim.py --check` is the only thing this repo can say about it.
