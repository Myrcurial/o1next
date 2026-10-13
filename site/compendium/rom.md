---
layout: page
title: "ROM and firmware"
subtitle: "The machine"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Issue:** #72. **Status:** first pass. The source has been indexed and its
port/vector tables extracted; every one of them **agrees with**
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3, which had been derived from the schematic and
from the running machine. That is the headline result: the map survives contact
with the primary source.

This is Osborne's own source for the machine's firmware — the thing the rest of
the project had been inferring. It is a safety copy of material already public
in several places; see "Provenance" at the end.

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
| `release.txt` | 53 | The 1985 Osborne letter granting FOG permission to reprint the schematics and BIOS listing. Retained verbatim — see [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md). |
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
image is [`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/os1-144.rom) (CRC32 `c0596b14`) — see
[`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md).

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

### Cross-check against [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3

| Map doc §3 | Source | Verdict |
|---|---|---|
| `2100–2103` floppy, 2100 stat/cmd, 2101 track, 2102 sector, 2103 data | `D.CMDR/STSR/TRKR/SECR/DATR` | **agrees** |
| `2201–2280` keyboard, one address bit per row | `H.KEY = 2200H`, read with A0–A7 one-hot | **agrees** |
| `2900–2903` IEEE-488 PIA, MC6821 (UC7) | `CPDRA/CCRA/CPDRB/CCRB` — a PIA with A/B data+direction+control, i.e. 6821-style | **agrees** |
| `2A00–2A01` serial ACIA, MC6850 (UC4) | `H.SCTRL/H.SSTS` at 2A00, `H.SXMT/H.SREC` at 2A01 | **agrees** |
| `2C00–2C03` video PIA, MC6821 (UC15) | `H.VIO = 2C00H`, ROM touches +0…+3 | **agrees** |

No contradictions. The I/O map in [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3 is now sourced
from the firmware as well as the schematic and the running machine.

**Free space within the window.** The firmware touches exactly five bases
(`2100`, `2200`, `2900`, `2A00`, `2C00`), so the clear gaps *between* the device
blocks are `2300–28FF`, `2B00–2BFF` and `2D00–2FFF`. That is where a virtual
peripheral belongs — but confirm the *decode granularity* against the schematic
before relying on an address *inside* one of the used blocks, because several
decode more than the registers the firmware names (the keyboard decodes A0–A7
one-hot, for instance). This narrows the recommendation in the map doc §7 and
closes most of gap 1 in [`docs/research-gaps.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/research-gaps.md).

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
matching [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §4. There is **no `OUT 0` or `OUT 1`
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
[`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3 remains schematic-level and is unaffected.

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
  sources at 60 Hz ([`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §5).
- `ENADIM` / `DISDIM` toggle the dim bit through `OUT 2` / `OUT 3` (above).

Individual register semantics stay in [`docs/o1-memory-io-map.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-memory-io-map.md) §3; this pass
records what the ROM does with them, not a re-derivation.

## What this closes, and what it does not

| Gap ([`docs/research-gaps.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/research-gaps.md)) | Status after this pass |
|---|---|
| **1** — exact memory & I/O map, free decode windows | **Substantially closed.** Every address the firmware touches is now sourced, and the gaps between the five device blocks (`2300–28FF`, `2B00–2BFF`, `2D00–2FFF`) are clear. Decode *granularity* is still schematic-level. |
| **3** — char-gen socket pinout | **Not addressed** — that is a hardware pinout, not firmware. Still open, still needed by #24. |
| **10** — 6850 ACIA location for the WiFi modem | **Closed** — `2A00`/`2A01` confirmed by an independent source. |
| **11** — floppy controller variant, port map, DD changes | **Port map and command set closed**; the DD changes are now documented (1.44 *is* the DD ROM, DD block = 1K, disk-type tables in the CBIOS). MB8877-vs-WD1793 remains open. |

Two things this pass adds that no existing doc had:

- the **monitor RAM map** (`0EA80–0EFFF`) and the interrupt vector table at `0EFF0H`;
- the **GPIB control codes and PIA handshake constants** for the IEEE port.

## Open questions / next steps

1. **Reassemble `rom144.asm` and compare against [`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/os1-144.rom)
   (CRC32 `c0596b14`).** A byte-for-byte match would prove the source *is* the
   shipped 1.44 ROM — and would validate the toolchain well enough to attempt
   **ROM 1.3** from `OSROM13.IMD`, which MAME carries as `NO_DUMP` (see
   [`docs/o1-rom-variants.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-rom-variants.md)).

   **Corrected 2026-10-13: this was the wrong question, twice over.** It is not a
   `z80asm` problem, and it is not a search for ACT 3.5e. `z80asm` is installed
   (`REQUIREMENTS.md`) and does **not** accept this source as it stands — the
   listing is written in the Osborne/ACT assembler's own syntax, with equates as
   `NAME = expr` (from line 26 onward) and the macros `LK`, `STO`, `LDK`, `JZ`,
   `JRZ`, `CMP`, `MSG`, `ECHO`, `DC`, `PROC` plus the `*SET` / `*[n]`
   directives; measured, `z80asm -o out.bin rom144.asm` stops on the first equate
   and writes a **0-byte** output. But porting that layer was never the right
   move, and 3.5e was never needed: the **vendor's own assembler is in the local
   archive** — `ACT80.COM`, SORCIM's "Assembly Code Translator", versions 3.0
   and 3.2 — and `tran.txt`'s own procedure (`ACT B:ROM144 H=B:`) runs it under
   MAME on a CP/M system disk ([`research/shipped-software/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/shipped-software/)). What the install
   *does* unblock is **writing** ROM code, which is what #83's `HCBOOT` body and
   any ROM 2.0 build need. The reassembly itself is tracked on #203.
2. **Does the 1.44 ROM's CBIOS match the 1.41 source?** The CBIOS is
   disk-loaded, so extract it from a shipped system disk (`OS1SYSD.IMD` /
   `OS1SYSS.IMD`) and diff it against the 1.41 build.
3. **Read the IEEE driver section (lines 3113–3400) against
   [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md)** to confirm the exact handshake the Drive C
   firmware expects (#6/#22).
4. **Pin down the video register semantics** from the ROM's write pairs
   (`+1`→`+0`, `+3`→`+2`) against the schematic (#24).

## Provenance

- The source tree: `github.com/BrettHallen/Osborne_1` `ROM/Source_Code_v144/`
  (all 18 file sizes match). See [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md).
- The 1.44 binary used for the CRC comparison: [`research/roms/os1-144.rom`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/os1-144.rom)
  (Don Maslin's archive) — identical to MAME's `3a10082-00rev-e.ud11`.
- The OCC engineering source disks (`research/source-code/*.IMD`, bitsavers)
  are the *disk* copies of the same material and have not yet been extracted —
  that is #2's pipeline work.
- Licensing: `release.txt` retains Osborne's 1985 FOG letter verbatim; the
  terms are recorded in [`research/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/research/README.md).
