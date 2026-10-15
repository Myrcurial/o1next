# rom-service — the ROM's window page 1, and the boot frame in flash

The firmware side of the ROM↔Pico channel: the **ROM service** command class
(`40–4Fh`) of the mailbox protocol, the two doors it answers on, and the boot
frame compiled into the RP2354's own flash. The contract is
`docs/rom-pico-protocol.md` (#247 step 8); this directory holds the frame asset
that contract names.

| File | What it is |
|---|---|
| `frame.bin` | the boot frame: **8192 bytes = two 4096-byte halves**, characters then attributes, each carrying its own `O1NEXT` magic and 16-bit sum at its own `0FF8h`. A **generated, committed** artifact — regenerate it with the command below and never hand-edit it |

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

## What is not here yet

- the C module: `PRESENT`, the two doors (`0E7h`/`0EBh` for userland, bank-2
  `2300h`/`2301h` for the ROM), the frame served out of flash
- the ROM's screen code and the `softrom_device` selector — #247's turns 1–4,
  which prove the sequence in the emulator first
