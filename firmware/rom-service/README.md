# rom-service — the ROM's window, the door, and the boot screen the RP2354B plays

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, and the **boot
screen** compiled into the RP2354B's own flash. The contract is
`docs/rom-pico-protocol.md` (#247 step 8); **#278** is where the ROM-side frame path
was retired, and "How the screen gets drawn" below is the summary.

The **C module is written (#284)**: `rom_service.c`/`.h`, host-tested and in CI, on
top of the engine in `firmware/library/`. What is still missing from this folder is
the **RP2354B's own video renderer** (#277), which needs PicoEm and a board.

## The module

| File | What it is |
|---|---|
| `rom_service.h` / `rom_service.c` | the `40–4Fh` class — `PRESENT` and `INFO` as an `mb_extension`, the payload as a port, the two doors named from `mailbox.h` |
| `test_rom_service.c` | the host suite: the door's transaction, the retired ids, the payload, and both doors |
| `run_tests.sh` | assembles the payload with `tools/research/rom2image.py`, then runs the suite |
| `boot-animation.bin` | the boot screen (below) — the one asset, and not generated here |

```sh
firmware/rom-service/run_tests.sh -v
```

No board, no SDK: one C compiler and python3. CI runs it
(`.github/workflows/rom-service.yml`).

**The payload is a port, not an asset.** The 3599 bytes page 1 holds are handed in
(`rom_payload`: a pointer and a length) the way `media.h` hands the library a
medium; on the board that pointer is into the RP2354B's own **XIP flash**, where a
pointer *is* the read. The suite hands in the bytes `tools/research/rom2image.py`
assembles from the repo's own archive, so it proves the module serves *the* payload
rather than a fixture that happens to fit. A module handed no payload answers `06h`
rather than pretending to present one.

**The suite is `romservice-check.sh`'s acceptance, on the host.** The checks the
emulator's `softrom_device` passes today are the ones this class has to pass when it
replaces it (`docs/emulation-testbed.md`, Gate D): the ECHO presence probe, `INFO`,
`NOP`, an unknown opcode, the abandon rule, `PRESENT(0)` answering `OK` with `1`,
`2` and `3` answering `09h` and leaving page 1 alone, and a transaction on one door
not disturbing the other. Two checks are the C module's own, because the stand-in
had no reason to make them: that no payload is `06h`, and that the request register
is write-only — reading it must not consume a reply.

**And the ROM's own client no longer drives the door at all (#278).** The 26-byte
screen code is the bright fill, the fallback print and the return — the Z80's role is
the *trigger*, and `PRESENT`/`INFO` now serve the userland client (`MOUNT.COM`, the
clock publisher) and the web UI. So "driving the ROM's own client against the
module" **is** the door's acceptance, and that is what this suite runs; there is no
separate ROM-side transaction left to replay.

## The asset

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

- **The RP2354B's own video renderer**: the shadow VRAM, the frame pacing, and the
  stop on the Z80's first write — #277, which is gated on PicoEm (#192) and proves it
  in the emulator first. What it draws is `boot-animation.bin`, and
  `tools/research/bootanim.py --check` is the only thing this repo can say about it.
- **The wiring that retires the stand-in.** The class is built and tested, but the
  emulator still answers the ROM's door with `softrom_device`'s C++ implementation:
  making the *firmware* answer it in picoem is the bridge's work (#286, #292), and
  `softrom_device` stays as the fallback and the oracle until then
  (`docs/emulation-testbed.md`, Gate D).
- **The board's door decode.** Which bank-2 cycles reach `2800h`/`2801h` and which
  I/O cycles reach `0E7h`/`0EBh` is the PIO bus tap and the personality work
  (#17, #179); the pin map is `hardware/interposer-upgrade/revb/README.md`. The module is
  door-agnostic — it is reached through `mb_extension`, which does not know a door
  exists — so both doors are a decode question and not a class question.
