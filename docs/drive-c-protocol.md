# Drive C: IEEE-488 RAM disk — reverse engineering notes

Source: research/drive_c/DRIVE_C.IMD (Osborne 1 SSDD, FM 10x256, 40trk).
Extracted with cpmtools (`osb1sssd` diskdef) to research/drive_c/extracted/.
Disassembly: z80dasm (see "Tool evaluation" below).

## Files on the disk

| File | Size | Role |
|---|---|---|
| DCL.COM | 6656 | "DRIVEC version 2.08" — driver installer/loader. Loads DFD.SPR, DCA/DCU. "Cannot install driver$Driver is already installed$" |
| DFD.SPR | 2560 | Resident driver (page-relocatable SPR). Contains CCP-style command table (DIR ERA HELP REN SAVE TYPE USER) + BIOS hook code |
| DCA.COM | 9984 | "DCA version 1.85" — assign/configuration |
| DCU.COM | 6272 | "DCU version 1.40" — RAM-disk utility (erase all, directory, files/line config; generates DCUN.COM via SAVE 28) |
| DCQ.COM + DCQ.DAT | 896+128 | "DCQ version 1.22" QUICKPAC — fast boot-time loader; DCLOADED.SYS marker |
| DCQINS.COM | 7296 | QUICKPAC installer (writes boot track via DCL); text by David E. Price |
| AUTOST.COM / DCQAUT.COM | 768 | Auto-starter: submits QUICKPAC at cold boot via $$$.SUB |
| PRN.TST | 7936 | Print test file (likely exercises the print-buffer feature) |
| PIP.COM, XDIR.COM | — | Utilities |

Author: Kenneth M. Toy, (c) 1983 Drive C. Also supports a print buffer
("Bad print buffer parameter, not loaded", "Not enough space for fixed
print buffer"). Osborne-1 only: "cannot be used with the Executive".

## Hardware interface (from DCL.COM disassembly)

The Drive C box hangs off the Osborne 1 **IEEE-488 option port**, driven by
bit-banging the motherboard's memory-mapped 6821 PIA. Everything below is read
from `research/drive_c/disasm/dcl.asm` (z80dasm, org 0x100) and cross-checked
against the raw bytes — see "Disassembling" at the end for how to regenerate it.

**PIA registers: `0x2900-0x2903`** in bank 2:

| Address | Register |
|---|---|
| `0x2900` | port A data |
| `0x2901` | port A control (CRA) |
| `0x2902` | port B data |
| `0x2903` | port B control (CRB) |

Bank switching is the O1's own: `OUT (0),A` selects bank 2 (I/O) and `OUT (1),A`
returns to bank 1, `DI`/`EI` bracketed — the same convention as the ACT hard-disk
BIOS (`occ1-harddisk-analysis.md`). Note this is the *host* selecting its own
bank; the Drive C box never sees it.

### The transport, in order (DCL.COM `0x16d5`-`0x1794`)

1. **Init.** `xor a` / `out (0),a` (bank 2), then CRA=`32h`, DDRA=`FFh`,
   CRA=`36h`, CRB=`32h`, DDRB=`FFh`, CRB=`36h` — ports A and B both outputs,
   CA2/CB2 in handshake-pulse mode.
2. **Address/command byte.** Port B (`0x2902`) ← `08h`, then a settle call
   (`sub_07b5h`).
3. **Sector/head byte.** Built from two variables and written to port B: bit 7
   from `l051ah` bit 7, and the low bits from `l0519h` encoded as
   `n >= 3 ? ((n-3) << 2) | 3 : n | 0Ch`. `00h` is written *first*, the settle call
   runs, then the computed byte — so the byte is staged with a gap between halves.
4. **Operation byte.** `88h` normally; `81h` when the transfer count wraps
   (`c+1 == 0`), and in that case port A is cleared to `00h` first. So `88h` and
   `81h` are the two operations, and they differ in whether a port A byte precedes
   them.
5. **Data.** 128 bytes, one at a time, between port A (`0x2900`) and a buffer via
   `LDI`, with a **strobe pulse per byte**: CRA ← `3Eh` then `36h` (set, then
   reset the CA2 pulse), `dec hl`, `LDI`.
6. **Teardown.** Port B ← `09h`, then the DDRs are re-arranged: CRA=`32h`,
   port A ← `FFh`, CRA=`36h`, port B ← `00h`, CRB=`BFh`, CRB=`04h`, port B ← `02h`,
   `out (1),a` (bank 1), `ei`.

The line that matters most for an emulated device is **`DDRB=BFh`**: bit 6 of
port B becomes an *input*, so the host is reading a status/ready line back from
the box. Everything else in the sequence is host→device.

### The transport lives in DCL.COM, not DFD.SPR

This doc previously implied DFD.SPR held the protocol. It does not:
`grep -E '290[0-3]h' dfd.asm` returns **nothing** — DFD.SPR never touches the PIA.
DCL.COM holds all 22 PIA references. DFD.SPR's only port access is a single
`OUT (0F1h),A` at `0x0803`, still unexplained (`F1h` is not a PIA address; likely
the double-density board or a status port).

So the split is **DCL.COM = transport + installer**, **DFD.SPR = the command layer
that drives it** (its own command table is DIR/ERA/HELP/REN/SAVE/TYPE/USER). How
DFD.SPR reaches the transport is the next thing to establish, because it makes no
direct PIA references — so it must be a patched vector or a relocation DCL
performs at install time.

### The manual says it is *not* real GPIB

Worth recording because it settles the direction of travel for an emulator:

> **IEEE-488 COMMUNICATIONS PROTOCOL IS NOT SUPPORTED ON THE Drive C
> PRINTER/HARD DISK/8088 EDGE CONNECTOR** — `Drive_C_Users_Manual.ocr.txt`

Drive C duplicates the *parallel port function* of the O1's IEEE-488 connector for
a printer, but does not speak GPIB protocol. With the bit-banged CA2/CB2 strobes
above, the working assumption is a simplified handshake over the same connector
rather than SRQ/EOI/ATN semantics — which is good news for emulation: the device
has to match a byte sequence, not a bus protocol.

## What the unit was like to use (contemporary reports)

Two letters in *The Portable Companion* #15 (Jan/Feb 1985, PDF p. 52) give the
user side of the unit. That matters to the reproduction (#84): it has to be worth
using, not merely protocol-correct.

> I've been using my **384K unit** for one month and it's turned my single density
> Osborne 1 into a totally new machine. … it takes **six seconds** to go from the
> editing no file menu in WordStar to the dot prompt in dBASE II. **Before I had
> Drive C: I had to boot up a new disk every time** I wanted to edit a program.
> That was minutes waiting while the Osborne booted up different files. … I had to
> shell out **$250 to Xerox for an exchange disk drive** two months ago. Now my
> **disk drives get 90% less wear** and I do 90% more work.
> — Martin Kilgore, South Pasadena, CA

And the reviewer, in the same issue, standing by a negative verdict:

> I still stand by what I wrote — **Drive C: is not a good buy for the average
> user**. … both of the readers who responded are doing precisely what I said the
> unit would be good at — **disk intensive operations for large parts of the
> day**.
> — Donald G. Krantz, Minneapolis, MN

So there was a **384K** configuration, and the disagreement was never about
whether it worked — it was about who it was for. Extract:
`research/technical-articles/TPC-Issue15-1985-pp52-drive-c-letters.pdf`.

## Open questions (next steps)

1. **How DFD.SPR reaches the transport.** It makes no PIA references at all, so
   either DCL patches a vector into it at install time or it calls a fixed
   relocated entry. This is the next step, because it unlocks the command layer.
2. **What the command bytes mean.** `08h` (address/command), the sector/head byte,
   `88h`/`81h` (the two operations), `09h` (teardown): which is read, which is
   write, and what the box replies on port B bit 6 and on port A. The ROM's own
   IEEE-488 implementation (`o1-rom-source.md`) is the *host* side of this same bus
   and should be cross-checked against it — two independent descriptions of one
   protocol, and a disagreement would be a finding.
3. **Capacity reporting, and the sector/head encoding**
   (`n >= 3 ? ((n-3) << 2) | 3 : n | 0Ch`). The `-3` and the `| 0Ch` need
   explaining against the disk's geometry.
4. **How DCL patches the O1 BIOS drive table to add C:** — BIOS jump-table hook
   points, and the DPB used for the RAM disk.
5. **Meaning of `OUT (0F1h),A`** at `0x0803` in DFD.SPR.
6. **PRN.TST / the print-buffer feature** — spooling to the Drive C box, or
   pass-through to the printer on its duplicated connector?
7. **DCL's CPU-detection snippet** (ports `0xD6` OUT / `0xDE` IN, and the
   `rla`/`rra`/`daa`/`cpl`/`scf`/`ccf` region near `0x0748`) — still unexplained,
   and not obviously related to Drive C.

The previous revision's question 5 — real GPIB, or a simplified handshake over the
same connector — is answered by the manual in the negative: *"IEEE-488
COMMUNICATIONS PROTOCOL IS NOT SUPPORTED"*.

## Disassembling

```
z80dasm -a -l -g 0x100 -o research/drive_c/disasm/dcl.asm research/drive_c/extracted/dcl.com
z80dasm -a -l -g 0x100 -o research/drive_c/disasm/dfd.asm research/drive_c/extracted/dfd.spr
```

**z80dasm 1.2.0** (`brew install z80dasm`) — the same version and flags as the
committed CoPower listings, so the two sets are directly comparable. It is a
linear sweep, so it misaligns around data tables: DCL.COM has a data and
jump-table region from roughly `0x0840`, and absolute `JP`/`CALL` targets that
land there are table bytes or loader-patched relocation points, not code. (The
`jp pe,00757h` / `jp pe,0763h` inside the data-transfer loop are the clearest
example: `0x0757 + 0x1000` is the loop's own body, so the loader is adding a page
offset when it installs the resident copy.) Read the listing with that in mind
rather than trusting it end to end.

cpmtools `cpmls`/`cpmcp` with the `osb1sssd` diskdef worked perfectly, once the
IMD was converted to raw with disk-analyse.
