# ROM 2.0's monitor source (#247)

This is **ROM 2.0's monitor**, and it is the vendor's source with one change in
it, not a rewrite:

| File | What it is |
|---|---|
| `rom2.diff` | the change to `../BIOS-144-source/rom144.asm`, as a unified diff |

There is no `rom2.asm` here on purpose. A second copy of a 4,655-line vendor file
would drift from the first one silently, and the whole point of ROM 2.0's monitor
is that it *is* the shipped 1.44 with new code in the free tail of it — the
CBIOS calls ROM routines by absolute address (`docs/o1-rom-2.0.md` §4.2), so a
byte moved anywhere below the new code is a moved anchor, not a feature. The diff
is the change; `tools/research/rom2asm.sh` applies it, assembles the result with
the vendor's own ACT80, and checks that nothing below the new code moved.

**The diff is against the *normalised* source** — `rom144.asm` as CP/M wants it,
CRLF, with the three stray CRs the capture has treated as the line breaks they
were. `rom144-reassemble.sh` normalises the same way, and `rom2asm.sh` does it
before applying this.

## What the change is

`HCBOOT` — the entry the monitor takes when **ESC** is pressed at the sign-on
prompt (`rom144.asm`, `JZ HCBOOT`). In 1.44 it is a documented stub, `JMP START`.
In ROM 2.0 it is the ACB-4000 cold boot: the same copy, patch and jump that
`HARD.COM`'s loader performs (measured at `HARD.COM` `0x01E5`–`0x0220`,
`docs/o1-rom-2.0.md` §4.6), with two differences the machine forces:

- **the source is the window, not a file on a disk.** The CBIOS is at `1000h` and
  the MD-10 BIOS at `1800h` in the softROM's window (`rom2image.py`'s layout), and
  `HCBOOT` runs in bank 2 where the window is visible. They are copied to `0E100h`
  and `0D800h`, which is where the stock system keeps them.
- **the patch source is `0E106h`, not `(page zero+1)+3`.** In bank 2 page zero
  *is* the monitor — a write there is dropped and a read returns the ROM's own
  bytes — so the shim's `LD HL,(0001H)` cannot be used as it stands. The ROM
  knows where it put the CBIOS; `HARD.COM` had to ask. `0E106h` is the CBIOS's
  vector 2, which is what `(page zero+1)+3` resolves to on a booted system.

The bank switch is last, and it is the CBIOS's own `SW2RAM` (`0E8E2h` in the
shipped bytes) with the MD-10 BIOS's entry pushed as its return address: the
monitor's code is *in* the bank it is switching away from, so the switch has to
be taken by code that survives it.

## Building it

```sh
tools/research/rom2asm.sh                       # -> /tmp/rom2-monitor.rom
tools/research/rom2asm.sh -o rom2-monitor.rom
```

It wants `mame`, `cpmcp`/`cpmrm` and `python3`, the same as
`rom144-reassemble.sh`, and it takes a few minutes: the assembly runs on an
emulated Osborne 1. The result then goes into the image with

```sh
tools/research/rom2image.py --monitor /tmp/rom2-monitor.rom -o /tmp/rom2.rom
```

and the emulated machine takes that image on its command line
(`-softrom /tmp/rom2.rom`). See `tools/emulator-setup/mame-osborne1nx/`.
