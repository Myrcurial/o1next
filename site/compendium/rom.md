---
layout: page
title: "ROM and firmware"
subtitle: "The machine"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Status: Solved.** The source is indexed and every
port and vector table it holds **agrees with** [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3,
which had been derived from the schematic and from the running machine; and
`rom144.asm` **reassembles with the vendor's own assembler to the shipped ROM,
byte for byte** (*The 1.44 reassembly*, below). What is not done: the 1.41 CBIOS
source has never been diffed against the CBIOS on a shipped system disk, and the
video register semantics are still read from the schematic rather than from the
source (*Open questions / next steps*). **Issues:** #72, #40, #203.

Osborne's own source for the machine's firmware — the thing the rest of the
project had been inferring — and the primary source for the interfaces the rest
of `docs/` builds against:

| Confirmed | Section |
|---|---|
| The five memory-mapped I/O bases — floppy `2100`, keyboard `2200`, IEEE-488 PIA `2900`, 6850 ACIA `2A00`, video `2C00` — agreeing with [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3 entry for entry | *The memory-mapped I/O map, as the source states it* |
| The monitor RAM map (`0EA80–0EFFF`) and the interrupt vector table at `0EFF0H` | *Monitor RAM and vectors* |
| The WD179x floppy command set the BIOS issues (#20) | *Floppy command set* |
| The IEEE-488 register programming, the GPIB command bytes, the inverted bus, and the *"IEEE always appears to be ready"* stub (#6/#22, #19) | *IEEE-488 — and the parallel printer is the same port* |
| The video write pairs (`+1`→`+0`, `+3`→`+2`) and `ENADIM`/`DISDIM` through `OUT 2`/`OUT 3` | *Video, as the ROM drives it* |
| A negative result: the firmware never selects its own bank — there is no `OUT 0` or `OUT 1` anywhere in the ROM | *Bank switching: what the ROM actually does* |

It is a safety copy of material already public in several places; see
*Provenance* at the end.

## The two components

The machine's firmware is **two separate programs**, and the source tree has one
of each:

| Component | Lives in | Source here | Rev |
|---|---|---|---|
| **Monitor ROM** — boot, video, keyboard, disk, IEEE-488, interrupt handlers | the 2732 at UD11 | `rom144.asm` | 1.44 |
| **CBIOS** — CP/M 2.2 character and disk BIOS | loaded into RAM from the system disk | `occbio*.asm` | 1.41 |

They version independently, so **do not assume the 1.41 CBIOS source is what
ships inside the 1.44 ROM.** The monitor ROM is the 4 KB in the socket; the
CBIOS is a RAM-resident overlay assembled to a specific system size (below).

## File index

`bios141.gen` is the build recipe, and it lists exactly the files present here,
so the set is complete:

| File | Lines | What it is |
|---|---|---|
| `rom144.asm` | 4655 | The monitor ROM, Rev 1.44, `ORG 0`. Z80. Roger W. Chapman, 2/4/1983. Title: "DOUBLE DENSITY ROM". Contains the memory-mapped I/O equates, RAM storage locations, IEEE/disk equates, monitor main loop, video, keyboard, disk drivers, the IEEE-488 interface and drivers, the parallel (Centronics) printer path, and the interrupt handlers. |
| `occtxt6.ast` | 374 | The shared equates file (`S=OCCTXT6.AST` in the build): port bases, ROM vectors, monitor RAM bases, character codes, disk-type constants. `occbio05.asm` says "*FOR USE WITH OCCTXT6.AST ONLY*". |
| `occbio05.asm` … `occbio95.asm` | 47, 145, 80, 70, 341, 141, 246, 60, 505, 66 | The CBIOS listing, split into ten sections. `05` is the title block and layout; `45` holds the disk control blocks (`DPBASE`, `DPHGEN`); `85` the I/O-byte dispatch and character devices. |
| `occram15.asm`, `occram25.asm` | 31, 175 | "Monitor RAM Storage" — the RAM-resident data area, `ORG MRAM`, assembled into both the ROM and the CBIOS. |
| `bios141.gen` | 56 | The generation procedure: needs ACT 3.5e, DDT 2.2, SYSGEN 2.1 and MOVCPM, and the twelve files above. |
| `tran.txt` | 61 | The 1.44 ROM release memo (Sai Kit, 2/4/1983): how the HEX and print files were generated, on a DD machine with a Corvus hard disk. |
| `release.txt` | 53 | The 1985 Osborne letter granting FOG permission to reprint the schematics and BIOS listing. Retained verbatim — see [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md). |
| `source.md` | 2 | Provenance (BrettHallen/Osborne_1 `ROM/Source_Code_v144/`). |

## Revision lineage

**Monitor ROM 1.44** — the header carries the delta from 1.43, which is the
useful part (it is a change log for the DD machine):

```
CBOOT  - added seek 10 tracks and home drive : tsk
GKEY   - fixed bell bug                      : tsk
SENDEN - changed the number of retrys to NRETRY
PSEKC  - added disk head settle delay
SELDRV - changed start up delay to 500 ms    : tsk
```

`NRETRY = 10` (disk retry count), `SLD_RCT = 3` (slide-key repeat), and
`BRTBIT`/`DIMBIT` (`80h`/`00h`) are defined at the top of the file. The 1.44
image is [`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1next/blob/main/research/roms/os1-144.rom) (CRC32 `c0596b14`) — see
[`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-rom-variants.md).

**CBIOS 1.41** — from `occbio05.asm`/`occbio15.asm`:

```
MSIZE = 59              ; 59K system
CCP   = 0CB00H          ; location of the CCP
BIOS  = ccp+1600h
BDOS  = ccp+806h
DDT R (relocation value) = 1F80H-BIOS
```

So the CBIOS is relocated for a 59K system, and `occbio15.asm` carries the
CP/M disk-type tables — `HSTSIZ = 1024` (blocking/deblocking buffer),
`FPYSIB = 2048/128` (SD block = 2K), `FPYDIB = 1024/128` (DD block = 1K),
`DSKS1 = 5` (single density, 256-byte sectors, single sided).

## The memory-mapped I/O map, as the source states it

Straight out of `rom144.asm` (`;MEMORY MAPPED I/O`, around line 83) and
`occtxt6.ast`:

| Address | Name in source | What it is |
|---|---|---|
| `2100H` | `D.CMDR` / `D.STSR` | Floppy: command (write) / status (read) |
| `2101H` | `D.TRKR` | Floppy: track |
| `2102H` | `D.SECR` | Floppy: sector |
| `2103H` | `D.DATR` | Floppy: data (read/write) |
| `2200H` | `H.KEY` | Keyboard |
| `2900H` | `CPDRA` / `PA.DTA` / `PA.DIR` | IEEE-488 PIA: port A data / direction |
| `2901H` | `CCRA` / `PA.CTL` | IEEE-488 PIA: control A |
| `2902H` | `CPDRB` / `PB.DTA` / `PB.DIR` | IEEE-488 PIA: port B data / direction |
| `2903H` | `CCRB` / `PB.CTL` | IEEE-488 PIA: control B |
| `2A00H` | `H.SCTRL` (W) / `H.SSTS` (R) | 6850 ACIA: control / status |
| `2A01H` | `H.SXMT` (W) / `H.SREC` (R) | 6850 ACIA: transmit / receive |
| `2C00H` | `H.VIO` | Video memory controls (the ROM also uses `+1`, `+2`, `+3`) |

`occtxt6.ast` names the same bases — `H.FDC = 2100h`, `H.KEY = 2200h`,
`H.IEEE = 2900h`, `H.SIO = 2A00h`, `H.VIO = 2C00h` — which is worth noting
because the CBIOS refers to the IEEE port as `H.IEEE`, not as a PIA.

### Cross-check against [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3

| Map doc §3 | Source | Verdict |
|---|---|---|
| `2100–2103` floppy, 2100 stat/cmd, 2101 track, 2102 sector, 2103 data | `D.CMDR/STSR/TRKR/SECR/DATR` | **agrees** |
| `2201–2280` keyboard, one address bit per row | `H.KEY = 2200H`, read with A0–A7 one-hot | **agrees** |
| `2900–2903` IEEE-488 PIA, MC6821 (UC7) | `CPDRA/CCRA/CPDRB/CCRB` — a PIA with A/B data+direction+control, i.e. 6821-style | **agrees** |
| `2A00–2A01` serial ACIA, MC6850 (UC4) | `H.SCTRL/H.SSTS` at 2A00, `H.SXMT/H.SREC` at 2A01 | **agrees** |
| `2C00–2C03` video PIA, MC6821 (UC15) | `H.VIO = 2C00H`, ROM touches +0…+3 | **agrees** |

No contradictions. The I/O map in [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3 is now sourced
from the firmware as well as the schematic and the running machine.

**Free space within the window.** The firmware touches exactly five bases
(`2100`, `2200`, `2900`, `2A00`, `2C00`), so the clear gaps *between* the device
blocks are `2300–28FF`, `2B00–2BFF` and `2D00–2FFF`. That is where a virtual
peripheral belongs — but confirm the *decode granularity* against the schematic
before relying on an address *inside* one of the used blocks, because several
decode more than the registers the firmware names (the keyboard decodes A0–A7
one-hot, for instance). This narrows the recommendation in the map doc §7 and
closes most of gap 1 in [`docs/research-gaps.md`](https://github.com/Myrcurial/o1next/blob/main/docs/research-gaps.md).

## Monitor RAM and vectors

The ROM's scratch area sits immediately below video RAM, and the emulator, the
video personality and any bus-level assertion need to know about it:

| Address | Name | Note |
|---|---|---|
| `0EA80H` | `MRAM` | Base of the monitor RAM area (`ORG MRAM` in `occram*.asm`) |
| `0EF00H` | `TEM` | Used in the boot routines |
| `0EF05H` | `RTRY` | Retry counter |
| `0EF08H` | `ROMRAM` | ROM/RAM flag |
| `0EF09H` | `DSTSB` | Six bytes of disk info |
| `0EF0FH` | `DMADR` | Disk DMA address |
| `0EF13H` | `SEKDEL` | Disk step delay |
| `0EF14H` | `SAVSEC` / `SAVTRK` / `SDISK` | Saved sector / track / disk |
| `0EF50H` | `HSTACT`, `UNASEC`, `LOGSEC` | Host active, unallocated/logical sector |
| `0EF59H` | `KEYLCK`, `CURS`, `LKEY`, `ESCH` | Keyboard lock, cursor, last key, escape |
| `0EF61H` | `PIAAD`, `PIABD` | Saved PIA A/B data — the IEEE port's shadow |
| `0EF6AH` | `DACTVE`, `BELCNT`, `LLIMIT` | Disk active, bell counter, line limit |
| `0EFF0H` | `INTBL` | Interrupt vector table |
| `0F000H` | `FWAVM` | First address of video memory |

Also from `occtxt6.ast`: `ROMVEC = 100H` (start of the ROM vector table),
`NMIA = 66H` (NMI vector), `BKPI = 0CFH` (breakpoint interrupt = 1),
`SEKTMO = 0FEH` (seek time-out status).

## Bank switching: what the ROM actually does

The ROM defines exactly two bank-related macros:

```
ENADIM: MACRO          DISDIM: MACRO
        OUT 2                  OUT 3
        ENDM                   ENDM
```

`OUT 2` / `OUT 3` set and clear the `BIT 9` latch (the "dim bit", bank 3) —
matching [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §4. There is **no `OUT 0` or `OUT 1`
anywhere in the ROM**: the firmware never selects the RAM bank itself, so
bank 1 ↔ bank 2 must be driven by hardware (reset and the NMI flip-flop chain),
exactly as §4 describes. This is a useful negative result for the interposer:
the firmware gives us no example of a software bank switch to model, and the
"never drive `0x00–0x03`" rule in §4 stands.

## Floppy command set

The WD179x commands the BIOS issues (`rom144.asm`, `;DISK EQUATES`):

| Constant | Value | Command |
|---|---|---|
| `D.SEK` | `010H` | Seek |
| `D.STP` | `020H` | Step |
| `D.STPI` | `040H` | Step in |
| `D.STPO` | `060H` | Step out |
| `D.RDS` | `080H` | Read sector |
| `D.WRTS` | `0A0H` | Write sector |
| `D.RDA` | `0C0H` | Read address |
| `D.FINT` | `0D0H` | Force interrupt |
| `D.RDT` | `0E0H` | Read track |
| `D.WRTT` | `0F0H` | Write track |

These are the type I/II/III/IV encodings of a WD179x-class part, which is what
the floppy interposer (#20) has to speak. The MB8877-vs-WD1793 part question in
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3 remains schematic-level and is unaffected.

## IEEE-488 — and the parallel printer is the same port

The ROM carries a complete IEEE-488 implementation (`;IEEE-488 INTERFACE.`,
line 2606, drivers from 3113), and it is the register-level contract for
Drive C (#6/#22) and for the virtual printer (#19).

Three things worth extracting immediately:

**The bus is inverted.** Line 2668: *"ALL SIGNALS ARE LOW ON THE IEEE BUS WHEN
PIA REGISTER CONTAINS '1'."* An emulated device that assumes positive logic
will be wrong.

**GPIB command bytes** (`;IEEE control codes`):

| Constant | Value | Meaning |
|---|---|---|
| `IE_TALK` | `40H` | make talker |
| `IE_UTLK` | `5FH` | make untalk |
| `IE_LSTN` | `20H` | make listener |
| `IE_ULST` | `3FH` | make unlisten |

**The PIA handshake programming** (`;IEEE EQUATES`), including
`PA.CDT = 00101110b` — *"to address port a data and set port a in input program
handshake mode"* — plus the direction values (`PA.DRO = 0FFH`, `PA.DRI = 00H`,
`PB.DR = 0BFH`, `PB.DTO = 00000010b`, `PB.DTI = 00001011b`) and the ready/strobe
bits (`PP.ORDY = 01000000b` in port B, `PP.IRDY = 10000000b` in the PIA control
register, `STRB = 00100000b` in port B). The current PIA state is shadowed in
RAM at `PIAAD`/`PIABD` (`0EF61H`/`0EF62H`).

And one behaviour that matters more than the register values: line 3133 says
*"IEEE always appears to be ready"* — the BIOS's device-status routine is
effectively a stub. **The O1 will not poll a GPIB device for readiness**, so an
emulated Drive C must be ready when addressed.

Finally, line 3249: *"The Parallel port is actually the IEEE port driven with
the centronix [protocol]"*. The MX-80 personality (#19) is therefore an
IEEE-488 device speaking Centronics on the same PIA, not a separate port.

## Video, as the ROM drives it

- `H.VIO` is written as **pairs** — `STO A,H.VIO+1` then `STO A,H.VIO`
  ("send data"), and `STO A,H.VIO+3` then `STO A,H.VIO+2` (lines 382–410).
- **Reading `H.VIO` clears the video interrupt** (line 2025,
  `LD A,H.VIO ;clear interrupt`) — the video PIA is one of the three IRQ
  sources at 60 Hz ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §5).
- `ENADIM` / `DISDIM` toggle the dim bit through `OUT 2` / `OUT 3` (above).

Individual register semantics stay in [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1next/blob/main/docs/o1-memory-io-map.md) §3; this pass
records what the ROM does with them, not a re-derivation.

## The 1.44 reassembly: the source *is* the shipped ROM (#203)

**Measured 2026-10-13.** `rom144.asm` assembles with the vendor's own assembler —
SORCIM's ACT80 — to an image **identical, byte for byte, to
[`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1next/blob/main/research/roms/os1-144.rom) (CRC32 `c0596b14`)**. That settles #83's deliverable
2: the source in this repository *is* the source of the shipped 1.44 monitor ROM,
and the toolchain that produced it runs under MAME.

| | |
|---|---|
| Assembler | `ACT80.COM` — SORCIM "Assembly Code Translator", **version 3.0**, safety copy in [`research/act-assembler/`](https://github.com/Myrcurial/o1next/blob/main/research/act-assembler/) |
| Command | `ACT80 B:ROM144 H=B:` — the vendor's own, from `tran.txt` |
| Reported | `no ERRORs,  473 Labels`, `Program LWA = 0FFFh` |
| Output | 11 520 bytes of Intel HEX, 255 records, `ROM144.HEX` on drive B |
| Image | 4096 bytes, CRC32 **`c0596b14`** — the shipped ROM |
| Reproduce | [`tools/research/rom144-reassemble.sh`](https://github.com/Myrcurial/o1next/blob/main/tools/research/rom144-reassemble.sh) — the happy path, end to end |

**This is the happy path, and it is self-contained in the repository.** The
assembler is the vendor's own, the command is the vendor's own, and both live
here: [`research/act-assembler/ACT80.COM`](https://github.com/Myrcurial/o1next/blob/main/research/act-assembler/ACT80.COM) and `tran.txt`. No substitution, no
porting, no search for a missing version — the toolchain that built the part is
the toolchain that rebuilds it.

### ACT 3.0 and 3.2 — and no 3.5e

The archive holds nine copies of `ACT80.COM`, and they are **three distinct
binaries over two versions**:

| Version | Copies under `…/rlee/` | md5 |
|---|---|---|
| **3.0** | `S/SORCIM/ACT Cross Assemblers/`, `M/MORROW/OUTSIDE SOFTWARE/ACT/`, `L/LOOSECPM/{079,109,262}/` | `4f76a911a66ddc8e1e02a1676c232d45` |
| **3.2** (serial 279) | `L/LOOSECPM/{073,087,119}/` | `cf73590466736fd1960e829b5f2221aa` |
| **3.2** (no serial line) | `D/DIGITAL RESEARCH/ECA/` | `88256731a9399dee68a29054865d072c` |

**`ACT 3.5e`, the version `bios141.gen` names, is not in the archive.** The
search was bounded rather than open-ended: every `ACT80.COM` under the archive
tree found by name, hashed and string-searched for its banner, and the tree
searched for an ACT `.DOC` or manual — the only hit was an unrelated
accounts-receivable file. `READ.ME` in the kit lists the 3.0 files exactly as
the archive holds them.

**All three builds are now safety copies in this repository** —
[`research/act-assembler/`](https://github.com/Myrcurial/o1next/blob/main/research/act-assembler/), with the 3.0 kit's own `READ.ME`, `DOCOP80.ASM` (every
ACT mnemonic, which is the file to diff against if a future source is rejected)
and its `LINK` include files; the provenance rows are in [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md),
and the licence notice in the kit's `READ.ME` is recorded there rather than
quietly dropped. The 3.2 builds sit beside it, so the byte-identical claim above
can be re-checked against a local file rather than the mirror:

```sh
O1_ACT80=research/act-assembler/3.2/ACT80.COM tools/research/rom144-reassemble.sh
```

[`tools/research/rom144-reassemble.sh`](https://github.com/Myrcurial/o1next/blob/main/tools/research/rom144-reassemble.sh) defaults to the 3.0 copy, so the build no
longer needs the local archive to be present. The third build — the one that
circulated inside a third-party bundle, `3.2/ACT80-eca-bundle.COM` — is **not a
drop-in**: it returns to the prompt printing nothing, where both SORCIM builds
assemble cleanly. It is held as a curiosity, not as a spare.

**The version gap turns out not to matter for this source.** 3.2 assembles
`rom144.asm` to a **byte-identical** hex file — same `no ERRORs`, same 473
labels, same `LWA = 0FFFh`, same 11 520 bytes. The only difference visible at
all is one line of the summary, where 3.2 says `8230h bytes not used` and 3.0
says `8232h`; that is ACT's own bookkeeping, not the object code. So 3.0 is not
merely "close enough" — for 1.44 it is exact, and the question of searching
further for 3.5e can be closed as not-needed.

So the reassembly needs neither `z80asm` — the wrong tool, because this is an ACT
job and not an 8080-syntax one — nor ACT 3.5e: the vendor's own assembler was in
the local archive all along, and 3.0 and 3.2 both give the object code exactly
(`REQUIREMENTS.md`).

**ROM 1.3 is the same exercise one revision earlier, and the assembler is the one
thing that did not carry over.** The source disk reads — it is an 8-inch 77-track
FM/MFM disk with CP/M skew 3, which [`tools/research/o1imd8.py`](https://github.com/Myrcurial/o1next/blob/main/tools/research/o1imd8.py) handles — the
source is extracted to [`research/source-code/ROM-13-source/`](https://github.com/Myrcurial/o1next/blob/main/research/source-code/ROM-13-source/), and the gap fill,
the terminator and the CRLF handling all carried over from this build. But the
1.3 source uses the `DBE`/`DCE` pseudo-ops, which only ACT **3.5E** has, and the
archive holds 3.0/3.2. The bytes those pseudo-ops emit are recovered from the
shipped rev-B ROM on `OCCROM.IMD`, and a 1.3 image can be built with a mechanical
source rewrite, but it is **not certified** — see [`docs/rom-13-reconstruction.md`](https://github.com/Myrcurial/o1next/blob/main/docs/rom-13-reconstruction.md)
and #205. The project still has no use for a 1.3 ROM — we build from the 1.44
source — so this remains upstream's gain and nothing here depends on it.

The caveats in *Four things the emulated build teaches about the source*, and the
damaged-record handling below, are the ones to carry into any other Osborne
source assembled this way.

### How the build is driven

The vendor's procedure (`tran.txt`) assumes two floppies: ACT80 in drive A, the
source in drive B, `ACT B:ROM144 H=B:`. Reproduced under MAME with two DD
images, and [`tools/research/rom144-reassemble.sh`](https://github.com/Myrcurial/o1next/blob/main/tools/research/rom144-reassemble.sh) is the whole of it:

1. [`research/shipped-software/OS1SYSD.IMD`](https://github.com/Myrcurial/o1next/blob/main/research/shipped-software/OS1SYSD.IMD) → raw (`imdinfo.py --raw`),
   `AUTOST.COM` removed, `ACT80.COM` added → **drive A**. It is a 250 kbps MFM
   40 × 5 × 1024 disk, and `cpmtools`' `osborne1` diskdef is the right
   description of it: the CBIOS's own DPB agrees field for field (`occbio95.asm`,
   `DPBGEN DSKD1,8*5,3,7,0,D1DSM,64,1100000000000000B,3` — 1 K blocks, `AL0/AL1`
   marking the two directory blocks, offset 3 tracks).
2. The same disk emptied of files, with `rom144.asm` normalised to CRLF and
   written as `ROM144.ASM` → **drive B**. The source is 83 KB and the hex file is
   12 KB; a full system disk has room for neither, which is the one thing that
   has to be arranged deliberately.
3. `o1raw2imd.py --dd` wraps both raw images (MAME will not open a bare sector
   image), `o1keys.sh` boots A with B in drive B and types the command, and
   `acthex.py` turns the hex back into an image and compares it against the
   shipped ROM.

### Four things the emulated build teaches about the source

- **`rom144.asm` as captured is LF-only, with three stray CRs** (offsets
  56 819, 59 483, 60 178 — lines 3198, 3334, 3383) where a line break lost its
  LF: `\tRET\r\tPAGE` is two lines, and so are the other two. CP/M text wants
  CRLF, so the *disk copy* is normalised CRLF → LF → CRLF, treating each stray CR
  as the break it was — **4658 lines rather than 4655**. The repository file is
  left exactly as captured.
- **The hex records do not cover the whole address space.** ACT emits a record
  only where the source put a byte, so `0x005C–0x0065`, `0x00E1–0x00FF` and
  `0x0FFF` are *gaps* — and the ROM holds **`00`** there, not `FF`. Filling the
  gaps with `FF` instead leaves 42 bytes wrong (`acthex.py --fill`). Worth
  knowing before the same exercise is run against ROM 1.3.
- **ACT's terminator is not Intel's.** The file ends with `:00010010` — a
  four-byte record carrying no data — rather than `:00000001FF`. Both 3.0 and 3.2
  emit it identically, so it is ACT's.
- **The program is `ACT80.COM`, not `ACT.COM`.** The vendor's memo says to type
  `ACT`, which on this kit is CP/M's `<name>?` — command not found — and reads
  exactly like an ACT usage error. It is not one.

### The one record that arrives damaged, and why it does not matter

On the floppy image, one record — `:100FC000…`, ROM addresses `0FC0–0FCF` —
reaches the host with **six non-hex bytes in place of six characters**
(`c0 de c0 de c0 0d`, at file offset 11 264: the first bytes of the file's last
1024-byte sector). The line is still 43 characters long, so nothing looks wrong
at a glance. Three facts pin it down:

- **It is not the assembler's doing.** ACT 3.0 and ACT 3.2 are different
  binaries and produce byte-identical output, *including those six bytes*. Two
  assemblers do not invent the same garbage.
- **It is not a general fault in the floppy path.** A `PIP` copy of the 83 KB
  *source* through the same disk — guest write, MAME image save — came back
  byte-identical, so writing a file whose last sector is partial is fine.
- **The intended content is fixed by ACT's own bytes.** The record's checksum is
  intact, and it is exactly the value 16 bytes of `FF` at `0FC0` produce, as the
  neighbouring all-`FF` records confirm (`41` at `0FB0`, `21` at `0FD0`, `11` at
  `0FE0`). The record therefore says what it should have held, and the range is
  restored from that (`acthex.py --recover-ff`).

With the range restored, the assembled image is **identical to
[`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1next/blob/main/research/roms/os1-144.rom) in all 4096 bytes** — and before the restore it
already agreed in the other 4080. The cause of the six bytes is not isolated; it
is deterministic, it lands in the file's last sector, and it is recorded here as
an emulation observation rather than explained away.

## What this closes, and what it does not

| Gap ([`docs/research-gaps.md`](https://github.com/Myrcurial/o1next/blob/main/docs/research-gaps.md)) | Status after this pass |
|---|---|
| **1** — exact memory & I/O map, free decode windows | **Substantially closed.** Every address the firmware touches is now sourced, and the gaps between the five device blocks (`2300–28FF`, `2B00–2BFF`, `2D00–2FFF`) are clear. Decode *granularity* is still schematic-level. |
| **3** — char-gen socket pinout | **Not addressed** — that is a hardware pinout, not firmware. Still open, still needed by #24. |
| **10** — 6850 ACIA location for the WiFi modem | **Closed** — `2A00`/`2A01` confirmed by an independent source. |
| **11** — floppy controller variant, port map, DD changes | **Port map and command set closed**; the DD changes are now documented (1.44 *is* the DD ROM, DD block = 1K, disk-type tables in the CBIOS). MB8877-vs-WD1793 remains open. |

Two things this pass adds that no existing doc had:

- the **monitor RAM map** (`0EA80–0EFFF`) and the interrupt vector table at `0EFF0H`;
- the **GPIB control codes and PIA handshake constants** for the IEEE port.

## Open questions / next steps

1. **Does the 1.44 ROM's CBIOS match the 1.41 source?** The CBIOS is
   disk-loaded, so extract it from a shipped system disk (`OS1SYSD.IMD` /
   `OS1SYSS.IMD`) and diff it against the 1.41 build.
2. **Read the IEEE driver section (lines 3113–3400) against
   [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1next/blob/main/docs/drive-c-protocol.md)** to confirm the exact handshake the Drive C
   firmware expects (#6/#22).
3. **Pin down the video register semantics** from the ROM's write pairs
   (`+1`→`+0`, `+3`→`+2`) against the schematic (#24).

## Provenance

- The source tree: `github.com/BrettHallen/Osborne_1` `ROM/Source_Code_v144/`
  (all 18 file sizes match). See [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md).
- The 1.44 binary used for the CRC comparison: [`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1next/blob/main/research/roms/os1-144.rom)
  (Don Maslin's archive) — identical to MAME's `3a10082-00rev-e.ud11`.
- The OCC engineering source disks (`research/source-code/*.IMD`, bitsavers)
  are the *disk* copies of the same material and have not yet been extracted —
  that is #2's pipeline work.
- Licensing: `release.txt` retains Osborne's 1985 FOG letter verbatim; the
  terms are recorded in [`research/README.md`](https://github.com/Myrcurial/o1next/blob/main/research/README.md).
