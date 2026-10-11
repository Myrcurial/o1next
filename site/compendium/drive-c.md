---
layout: page
title: "Drive C: the IEEE-488 RAM disk"
subtitle: "Peripherals and storage &middot; partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Source: research/drive_c/DRIVE_C.IMD (Osborne 1 SSDD, FM 10x256, 40trk).
Extracted with cpmtools (`osb1sssd` diskdef) to research/drive_c/extracted/.
Disassembly: z80dasm (see "Tool evaluation" below).

## Files on the disk

| File | Size | Role |
|---|---|---|
| DCL.COM | 6656 | "DRIVEC version 2.08" — driver installer/loader. Loads DFD.SPR, DCA/DCU. "Cannot install driver$Driver is already installed$". Per the vendor's review it **replaces the earlier `DRIVEC.COM`**, and when the print buffer is switched on it copies `DCU.COM` into the unit |
| DFD.SPR | 2560 | Resident driver (page-relocatable SPR). Contains CCP-style command table (DIR ERA HELP REN SAVE TYPE USER) + BIOS hook code. The vendor describes it as "**a substitute console command processor (CCP)**" that is "**automatically loaded**" |
| DCA.COM | 9984 | "DCA version 1.85" — the **Archive-Retrieve** program per the vendor's own review (it "replaces both `DCARCH.COM` and `DCRET.COM`"). The earlier "assign/configuration" label came from the disassembly and is questioned below |
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
from [`research/drive_c/disasm/dcl.asm`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/disasm/dcl.asm) (z80dasm, org 0x100) and cross-checked
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
[`research/technical-articles/TPC-Issue15-1985-pp52-drive-c-letters.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue15-1985-pp52-drive-c-letters.pdf).

## The vendor's software set, from a contemporary review

*The Portable Companion* #14 (Nov/Dec 1984), printed pp. 41–45 = PDF pp. 43–47,
carries **"Review of New Drive C: Loader & Archive Programs" by Larry Walker** —
and, usefully for provenance, it is a **reprint from *FOGHORN* (First Osborne
Group) 9/84**. It documents the second-generation Drive C: software, which is
what this disk holds, and it names each program and its job:

| Program | What the review says it is |
|---|---|
| `DCL.COM` | the loader "that makes the Drive C: unit accessible", replacing `DRIVEC.COM`; also turns the print buffer on, and then copies `DCU.COM` into the unit |
| `DFD.SPR` | "**A substitute console command processor (CCP)**, DFD.SPR is designed to make Drive C: work better and is **automatically loaded**" |
| `DCA.COM` | the **Archive-Retrieve** program, replacing both `DCARCH.COM` and `DCRET.COM` |
| `DCU.COM` | the print-buffer utility, loaded into the unit with the buffer; `DCU` gives a menu, `DCU E` erases every file |
| QuickPac: `DCQ.COM`, `DCQINS.COM`, `DCQ.DAT`, `DCQAUT.COM` | `DCQ.COM` "allows you to store a series of commands in SUBMIT fashion to load Drive C:, name it, copy the contents of a disk (or disks) into it, select a print buffer option, and run a program at the end of the process"; `DCQINS` is the menu-driven installer, writing the ASCII `DCQ.DAT`; startup becomes automatic by renaming `DCQAUT.COM` to **`AUTOST.COM`** |
| `DCN.COM` | "**automatically generated and loaded into Drive C: when the loader program is run**" — it backs the `DCN` rename command |
| `PRN.TST` | the print test file, sent to the printer at the end of installation |

The archive lineage is spelled out too: `DCARCH.BAS` (needed MBASIC, "very
slow") → `DCARCH.COM` (compiled, "bugs that arose when it was called upon to
close files") → `DCA.COM`.

### Command syntax of this generation

- `DC1 A` — install the unit and name it logical A. **This replaces
  `DRIVEC A: C:`**, which named the unit A and the left floppy C in one go.
- `DCN x` — rename the unit to logical name `x` at the CP/M prompt.
- `DC1 A16` … `DC1 A128` — as above plus a **fixed print buffer of 16, 32, 48, 64,
  80, 96, 112 or 128K**. Substituting `P` installs the **dynamic** buffer — all
  otherwise unused memory, released back to programs as the buffer drains. Any
  other letter means no buffer is installed.
- `DCU` — buffer menu (stop/restart the dump, clear the buffer, report dynamic
  space); `DCU E` erases the unit.
- `DCA RB` — run Archive-Retrieve in **Retrieve** mode from drive B:.

### Behaviour, and one gotcha that matters for emulation

- **A printer that is connected but switched off crashes the machine.** The
  review is explicit: *"If the printer is connected but OFF, the Loader will not
  work and the Osborne 1 will crash."* Cables must meet OCC's specification, and
  some printers (the reviewer's Daisywriter 2000) "look funny" to the unit — the
  fix being to disconnect the cable or leave the printer on. This is a property
  of the duplicated printer port, so a personality for #84 has to reproduce the
  failure and not only the success.
- **The reset button does not lose the unit's contents** — "only turning off the
  computer does that" — with the obvious advice to save first.
- **Archived files are stored contiguously as a single file** and are only
  readable through Retrieve; the directory shows one entry. A set spanning two
  disks names the second `filename.AR2`. The program warns when the target disk
  is not blank, shows its directory, and asks twice before erasing.
- **Speed**, as measured by the reviewer: `WSMSGS.OVR` (34K) retrieved into the
  unit in **10 seconds** versus **17** with PIP; a 272K WordStar + Spellguard set
  in 115 seconds. Single-density owners need two disk changes and take longer.
- **Cabling**: the unit mounts in the pocket below the right drive; the longer
  cable goes to the **IEEE-488 connector on the left side**, the shorter to the
  **External Video port** directly below the unit. Both O1 connectors are
  duplicated on the Drive C: panel (Centronics printer cable and shorting plug),
  and the unit has its own external video jack, so no adapter is needed.
- **Capacities sold**: 192K and 384K (the reviewer bought 384K).
- **Terms**: the new package was free to customers who bought after **31 December
  1983**, $39 to earlier ones; the manual runs to nearly 150 pages.
- **BackPac** — a battery pack inside the keyboard enclosure that holds the unit's
  memory for **8–10 hours** after power is lost, "deliberately or through power
  failure". Announced but not shipping at the time of writing, manual still being
  written, target price **$150**.
- The same vendor resold **Trantor** hard disks at a discount. The Trantor
  advertisement itself (*The Portable Companion* #5, February/March 1983,
  PDF p. 28; extract
  [`research/technical-articles/TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf))
  shows what the product was: the **TSL-5** and **TSL-10**, **5 MB $2995 /
  10 MB $3395**, *"unpack your disk, **plug it into the IEEE port**, run a simple
  5 minute installation procedure"*, supplied *"complete with BIOS, back-up,
  retrieve utilities and cable"*. So Trantor's Winchester is a **third
  IEEE-488-attached** storage device on this machine alongside Drive C — one more
  claimant on the port that #84 has to arbitrate.

Extract: [`research/technical-articles/TPC-Issue14-1984-pp43-47-drive-c-loader-and-archive-programs.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue14-1984-pp43-47-drive-c-loader-and-archive-programs.pdf).

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
8. **`DCA.COM`'s role** — the vendor's review calls it the Archive-Retrieve
   program and makes it the centrepiece of the new software; our table says
   "assign/configuration". Both may describe different versions, but the label
   came from the disassembly, so the disassembly is what needs re-reading.
9. **`DCN.COM`** — "automatically generated and loaded into Drive C: when the
   loader program is run". Which build step emits it, and where in `DCL.COM`?

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
