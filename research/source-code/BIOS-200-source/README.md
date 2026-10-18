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
the vendor's own ACT80, and checks that nothing below the new code moved — with
**one** deliberate exception, the sign-on dispatch's two key bytes, which it
checks *by value* rather than merely tolerating (the second hunk below).

**The diff is against the *normalised* source** — `rom144.asm` as CP/M wants it,
CRLF, with the three stray CRs the capture has treated as the line breaks they
were. `rom144-reassemble.sh` normalises the same way, and `rom2asm.sh` does it
before applying this.

## What the change is

`HCBOOT` — the entry the monitor takes when **RETURN** is pressed at the sign-on
prompt (`rom144.asm`, `JZ HCBOOT`; #247 step 4). In 1.44 it is a documented stub,
`JMP START`.
In ROM 2.0 it is the ACB-4000 cold boot: the same copy, patch and jump that
`HARD.COM`'s loader performs (measured at `HARD.COM` `0x01E5`–`0x0220`,
`docs/o1-rom-2.0.md` §4.6), with three differences the machine forces:

- **the source is the window, not a file on a disk.** The CBIOS is at `1000h` and
  the MD-10 BIOS at `1800h` in the softROM's window (`rom2image.py`'s layout), and
  `HCBOOT` runs in bank 2 where the window is visible. They are copied to `0E100h`
  and `0D800h`, which is where the stock system keeps them.
- **the patch source is `0E106h`, not `(page zero+1)+3`.** In bank 2 page zero
  *is* the monitor — a write there is dropped and a read returns the ROM's own
  bytes — so the shim's `LD HL,(0001H)` cannot be used as it stands. The ROM
  knows where it put the CBIOS; `HARD.COM` had to ask. `0E106h` is the CBIOS's
  vector 2, which is what `(page zero+1)+3` resolves to on a booted system.
- **the hand-over's store has to run in RAM, so `HCBOOT` copies it there.** The
  ROM's 60 Hz handler returns *through the CBIOS* at `CCPADR + 1633h`, and
  `CCPADR` is the ROM's own `CBOOT`'s to write — `HARD.COM`'s loader never did, and
  without it the machine stops at `1633h` for ever (`docs/o1-rom-2.0.md` §4.6).
  `HCBOOT` copies a 14-byte stub out of the payload's spare (`1E01h`, from
  `tools/research/rom2image.py`) into RAM at `0E0F0h` and pushes *that* address,
  so the store lands before the MD-10 BIOS runs. The stub writes `CCPADR`, the
  CBIOS's IOBYTE default, and jumps to `0D800h`.

The bank switch is last, and it is the CBIOS's own `SW2RAM` (`0E8E2h` in the
shipped bytes): the monitor's code is *in* the bank it is switching away from, so
the switch has to be taken by code that survives it. What is pushed as its return
address is therefore the stub in RAM, not the MD-10 BIOS's entry.

As built it is **77 bytes**, `0F67`–`0FB3`.

**And since #278 the tail holds the boot screen too**: the frame path's retirement
left the screen's code at **26 bytes** — fill the attribute array bright, print the
fallback, return — so it fits the 72 bytes the stub used to occupy, and the monitor's
new code is `0F67`–`0FCD` (**103 bytes**, **46 free** to the guard, up from 21).
`tools/research/rom2asm.sh` reports both numbers and checks the code's 26 bytes *by
value*.  The build's hex **is** damaged by the emulator's write-back
(`docs/rom-13-reconstruction.md` 7), and every case anyone has seen is undecodable
and caught loudly; the by-value check is there for the shape nobody has seen -- a
corruption whose bytes happened to be valid hex, which would decode and pass every
other check.

## The hunks

**1. The boot keys (#247 step 4), and they are two bytes.** The sign-on dispatch
(`rom144.asm` ~295-309) is three comparisons, and the change is *in place*:
`CMP ESC` becomes `CMP CR`, so `RETURN` is the machine's own hard disk, and
`CMP CR` becomes `CMP ':'`, so `:` is floppy A. `"` is unchanged, and `ESC` is
released — it falls through to the prompt's `JR START` like any unclaimed key. No
code is added, no address moves, and the new code's extent is unchanged at
`0F67`–`0FB3`. `START` clears `0EF00h`-`0EFEFh` on every pass — `DSKSWP`
(`0EFC7h`) included — which is what makes `:` reliably drive A. These are the
only bytes below `0F67h` that ROM 2.0 moves (`0x0048` and `0x0050` in the image),
and `rom2asm.sh` and `rom2image.py` both check them *by value*, so a monitor
carrying the old map — or a third value — stops the build with the map in the
message.

**2. `HCBOOT`, in the free tail above `0F67h`.**

**3. The boot screen, in the rest of that tail (#247, #278).** `SCRN` — what the
sign-on hook calls — fills the attribute array bright, prints the fallback and
returns. It used to be a stub that asked the interposer for a 4096-byte page of code
and ran it out of RAM; the frame path's retirement took the frame's trailer checks
and blits with it and left the trigger.

**4. `IMSG`'s own slot at `019Fh` (#278).** The vendor's 182-byte sign-on message is
replaced by ROM 2.0's 72-byte fallback — the animation's own two lines, at its own
rows and columns, with its own bright/dim runs, which is the *trigger* the RP2354B
watches for — and 110 bytes of the vendor's `FF` fill behind it. **The slot keeps its
length**, because nothing below `0F67h` may move: the CBIOS calls ROM routines by
absolute address (`docs/o1-rom-2.0.md` 4.2) and there is no `ORG` between `IMSG` and
the tail to absorb a shorter one. The 110 bytes are what 4.7's signature and extension
table will take.

So two regions below `0F67h` differ: the sign-on prompt and `IMSG`'s slot. Everything
else below `0F67h` is byte-identical to the shipped 1.44, and `rom2asm.sh` and
`rom2image.py` both measure that.

## Building it

```sh
tools/research/rom2asm.sh                       # -> /tmp/rom2-monitor.rom
tools/research/rom2asm.sh -o rom2-monitor.rom
```

It wants `mame`, `cpmcp`/`cpmrm` and `python3`, the same as
`rom144-reassemble.sh`, and it takes a few minutes: the assembly runs on an
emulated Osborne 1. It takes **no `-b` any more**: the screen's code is in the
monitor's tail, so there is no second artifact to extract (#278). The result goes
into the image with

```sh
tools/research/rom2image.py --monitor /tmp/rom2-monitor.rom -o /tmp/rom2.rom
```

and the emulated machine takes that image on its command line
(`-softrom /tmp/rom2.rom`). See `tools/emulator-setup/mame-osborne1nx/`.
