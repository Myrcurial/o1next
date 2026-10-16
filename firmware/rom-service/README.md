# rom-service — the ROM's window page 1, and what the interposer serves in it

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, and the two
assets the Pico serves out of its own flash. The contract is
`docs/rom-pico-protocol.md` (#247 step 8); this directory holds the assets that
contract names.

| File | What it is |
|---|---|
| `frame.bin` | the boot frame: **8192 bytes = two 4096-byte halves**, characters then attributes, each carrying its own `O1NEXT` magic and 16-bit sum at its own `0FF8h`. A **generated, committed** artifact — regenerate it with the command below and never hand-edit it |
| `screen.bin` | the boot screen's **code**: 4096 bytes, the window page the monitor's stub asks for with `PRESENT(3)` and copies to RAM at `4000h`. The code is the first 183 bytes; the rest is the vendor's own `FFh` fill; and the top of the page carries a trailer the code never reads — `O1NEXT`, the digest of the source it came from, and a 16-bit sum. Also **generated and committed** |

Regenerate the frame, from the repo root:

```sh
tools/research/rom2strokes.py --frame firmware/rom-service/frame.bin
```

`tools/research/rom2strokes.py --check` re-builds it from
`research/boot-screen/o1next-art.txt` and compares bytes, so the art and the
asset cannot drift.

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

## What is not here yet

- the C module: `PRESENT`, the two doors (`0E7h`/`0EBh` for userland, bank-2
  `2800h`/`2801h` for the ROM — *not* `2300h`/`2301h`, which is the floppy's
  track register and the keyboard's row 0; `docs/rom-pico-protocol.md` 2), the
  frame served out of flash
- `PRESENT(3)` in `softrom_device` and the screen harness — #247's turns 4 and 5,
  which prove the sequence in the emulator first. The screen's code is written and
  assembles (`research/source-code/BIOS-200-source/rom2-screen.asm`), and
  `screen.bin` is extracted from that build; what is missing is the device slot
  that serves it and the check that reads the video RAM back.
