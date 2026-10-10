# Research gaps — status review

**Last reviewed:** 2026-10-10, after the archive drop (#71), the ROM-source
indexing (#72) and the MAME work (#79).

This is the single place that says, for every open research question, **whether
it is answered, by what evidence, and what is left** — cross-checked against the
`research`-labelled issues. When the two disagree, one of them is wrong.

**Status words** (same vocabulary as `docs/README.md`):

| Status | Means |
|---|---|
| **Solved** | Answered, and the answer is checkable from a doc |
| **Partially** | The shape is known; a *named* sub-question is not |
| **Open** | Not answered |
| **Superseded** | Stopped mattering — a better route was found, or a decision was taken |

A gap is only **Solved** if the evidence is written down. "We know this" is not a
status.

## Summary

| | Count |
|---|---|
| Solved | 6 of the original 15 |
| Partially | 6 |
| Open | 1 |
| Superseded | 2 |

**What actually blocks the next phase** — everything else can wait:

1. **#39** — the identity of the three target machines (user action; blocks gap 12).
2. **Drive C's command set** — blocks #6/#22, and therefore the standalone Drive C
   reproduction (#84).
3. **#79** — the Nuevo system disk does not boot under MAME. *No longer blocking:*
   the decision taken is not to chase it, and to build the video personality from
   the ScreenPac design plus OZROM's soft 52/80/104-column switch.

Everything else is either done, or is research that can proceed in parallel.

---

## A. The original gaps

| # | Gap | Status | Evidence | Issues | What's left |
|---|---|---|---|---|---|
| 1 | Exact memory & I/O map, free decode windows | **Solved** | `o1-memory-io-map.md` §2–§7 (schematic), confirmed from the ROM source in `o1-rom-source.md`, measured on the running machine by `tools/check_o1_map.sh` | #40, #62, #64, #72 | Decode *granularity* is still schematic-level. Free gaps between the five device blocks: `2300–28FF`, `2B00–2BFF`, `2D00–2FFF` |
| 2 | NMOS vs CMOS Z80 across the target machines | **Superseded** | Resolved by history: the CMOS Z84C00 shipped in 1985, O1 production ended in 1983 — every O1 is NMOS. Interposer standardised on 74AHCT/HCT | #39 | #39's remainder: machine IDs and date codes, for the record |
| 3 | Z80 socket **and** char-gen socket pinout | **Solved** | Z80: datasheet, schematic sheet 3 of 9, `tools/check_schematics.py`. UA15: read at 1200 dpi off **sheet 4 of 9** (not the video sheet) — plain Intel 2716 pinout, `/CE`+`/OE` grounded, pin 21 strapped +5 V; address = `(scan<<7) \| char`; outputs serialised by UA14 (74166). `o1-mainboard-schematic.md` §4a, `o1-memory-io-map.md` §6, asserted in `tools/check_schematics.py` | #62, #24, #64 | — |
| 4 | CoPower-88 monitor ROM dump | **Superseded** | The SWP co-processor ROM is **in the repo**: `research/roms/swp-p88.rom`, 8088 code, from Maslin's archive. The board and interposer are common across hosts; only the driver varies | #3, #4, #5, #70 | Confirm the residual doorbell/IRQ semantics *from that ROM* rather than by inference |
| 5 | Power budget | **Solved** | Decision taken: the interposer gets its own 5 VDC feed near the Z80 socket, sized for Pico 2 W bursts (~300 mA+) | #12 | — |
| 6 | CoPower-88 protocol | **Partially** | `copower88-protocol.md` (Kaypro↔Zorba driver diff), `copower88-schematics.md` (SWP 611-0003), plus the 8088 ROM | #3, #4, #5, #23 | Doorbell/IRQ semantics; the 611-0003 sheet-4 comparator reference value; consolidate into one authoritative spec |
| 7 | Drive C IEEE-488 protocol | **Partially** | `drive-c-protocol.md`; `DRIVE_C.IMD` extracted and disassembled (`research/drive_c/disasm/`); the ROM's IEEE-488 implementation gives the PIA programming, the GPIB command bytes and the "always ready" stub behaviour (`o1-rom-source.md`); and the **byte transport is now read from `DCL`** — PIA init, the 128-byte strobed transfer, the operation bytes `88h`/`81h`, port B bit 6 as the device status input. The transport is in `DCL`, **not** `DFD.SPR` (which makes no PIA references at all) | #6, #22, #84 | How `DFD.SPR` reaches the transport; the meaning of the command/address bytes; capacity reporting. The manual settles one thing: real GPIB protocol is *not* supported on the Drive C connector |
| 8 | RT-60A register map | **Partially** | `rt60a-analysis.md`, reconstructed from the manual | #7, #18 | A read against a real unit — or a re-dump; the bitsavers TD0 is a damaged dump (27 no-id sectors) |
| 9 | OCC1 hard disk | **Partially** | `occ1-harddisk-analysis.md`; **and the archive drop showed there are two distinct products, not one** (see §B1) | #8 | The controller command sets, the default port, and a re-check of the doc's `0x2A00`/`0x2C01` claim — those are the ACIA and video PIA addresses, so something there is misread |
| 10 | 6850 ACIA location for the WiFi modem | **Solved** | `o1-memory-io-map.md` §3: `2A00`/`2A01`, UC4 — confirmed independently by the ROM source | #21 | — |
| 11 | Floppy controller, port map, DD changes | **Partially** | Ports `2100–2103` and the full WD179x command set from the ROM source; 1.44 *is* the DD ROM; DD block = 1K; the Nuevo and Osmosis DD boards are documented | #20, #30, #73 | MB8877 vs WD1793 (schematic-level); the DD upgrade's electrical changes |
| 12 | Which three machines, which board revisions | **Open** | — | #39 | **User action**: machine IDs (one is 24187A) and Z80 markings |
| 13 | A known-good boot disk per machine | **Solved** | Measured 3×3 matrix in `mame-emulation.md` §4: all three `-blank.imd` system disks boot on all three MAME machines; diagnostics disks also archived | #29, #70 | The *Nuevo system* disk (`OS1NUEVO.IMD`) does not boot — #79, closed as not needed — but the gap as stated is met |
| 14 | Consolidate into per-device protocol specs | **Partially** | Done: `copower88-protocol.md`, `drive-c-protocol.md`, `rt60a-analysis.md`, `o1-rom-source.md`, `o1-rom-variants.md`, `mame-emulation.md` | #75 | Missing: floppy, hard disk, printer/parallel, keyboard. #75 (the book) is the final consolidation |
| 15 | Memory-resident vs pure I/O-port for virtual devices | **Solved** | Recommendation stands: pure I/O-port, in the free windows from gap 1 (`o1-memory-io-map.md` §7) | #12, #16 | Same decode-granularity caveat as gap 1 |

---

## B. Questions that appeared since the original review

### B1. There are **two** hard-disk products, not one — three storage routes in total

The original gap 9 assumed a single OCC1 hard disk. The archive drop (#71) turned
up a second, unrelated one. Confirmed from their own strings:

| | ACT hard disk | Media Distributing / Adaptec |
|---|---|---|
| Source | `research/harddisk/OCC1_HARDDISK.IMD` | `research/adaptec/*.img` |
| Vendor string | `AUSTRALIAN COMPUTER & TELECOMMUNICATIONS  COPYRIGHT (C) 1982` | `Copyright (c) September 1983, Media Distributing` |
| Versions | `Version 31.05.82`, `Version 9-02-81` | `HARD version 1.93`, `PORTCHNG version 1.92`, `PREP version 1.93` |
| Controller | its own; `Enter disk controller address (` | Adaptec ACB-4000; `Enter starting port address in hex`, `must be on a 4 port boundary` |
| Utilities | `BOOTHD`, `LOADBIOS`, `HARDBIOS.HEX`, `MOVCPM10/5/F`, `DISKEDIT`, `DISKTEST`, `RESTORE`, `SAVEFILE` | `MD10.COM`, `MD20.COM`, `HARD.COM`, `HARDBIOS.SPR`, `HARDBDOS.SPR`, `HARDCCP.SPR`, `HD00/HD04BIOS.SPR`, `PREP.COM`, `PORTCHNG.COM`, `DRIVETBL.DAT` |

So the three ways to get more storage than 2 × 182 KB are the **ACT hard disk**,
the **Media Distributing/Adaptec hard disk**, and **Drive C** (IEEE-488). Both
hard disks use a *port-relocatable* controller — which matters, because the O1's
I/O decode is sloppy, so "4 port boundary" is the same two-address-line decode the
rest of the machine uses.

Drive C is the only one of the three buildable without unobtainable hardware —
see #84.

### B2. Character-generator ROM variants — closed

#44 asked for the early-font and Nuevo char-gen variants. Both are captured and
catalogued (`o1-rom-variants.md`): `5297c109` (early, paired with BIOS ≤ 1.4) and
`6c1eab0d` (late, paired with 1.43/1.44 and used by ScreenPac and Nuevo alike).
Open sub-question: nobody has rendered the two fonts side by side to confirm they
actually differ.

### B3. The Nuevo system disk does not boot under MAME — #79, **closed**

`OS1NUEVO.IMD` carries the Nuevo 80-column CBIOS 1.5, loads, prints its banner,
and stops. The pristine upstream copy behaves identically, so it is not a bad
conversion. The three plain DD system disks *do* boot the Nuevo machine, at 80
columns (`mame-emulation.md` §2, §4).

**Decision: not pursued.** Nothing in the Nuevo design has turned up a feature
worth the validation cost, so the video personality (#24) is built from the
**ScreenPac design plus OZROM's soft 52/80/104-column switch**, and the Nuevo
board stays prior art (#73). The residual question — MAME fidelity gap, or a
physical-card dependency — is recorded in `mame-emulation.md` §4 and only
matters if the Nuevo path is ever reopened.

### B4. OZROM 1E — a third-party ROM usable as tooling — #81

It boots under MAME (via BIOS substitution) and its manual documents a software
52/80/104-column switch, a chip-level memory tester, a redefinable keyboard, and
its own ROM jump table and memory map. It also **removes the IEEE-488 routines
entirely** — the vectors at `013F–0156` now deliberately crash the machine, and
*"IEEE-488 AS IOBYTE DEVICE 3 NOW NULL DEVICE"* — so **OZROM and Drive C are
mutually exclusive** without reimplementing the driver. It also shrinks the video
window to 3 KB (`F000–FBFF`) to make room for its keyboard features, which
constrains any 2.0 ROM (#83).

### B5. Other open research items

| Item | Issue | State |
|---|---|---|
| Nuevo + Osmosis upgrade boards as prior art (two products each; neither matches OCC's implementation) | #73 | Material archived; write-up outstanding |
| Archive provenance TODOs (2 items) | #74 | Needs the user's memory |
| `cpmtools` misreads Kaypro DSDD images | #35 | Low priority — `tools/cpmfs.py` replaces it; the upstream fix is a courtesy |
| G2 multi-format diskette read/write | #30 | Open design work |
| Case + power research (1:1 replacement board, "lunchbox") | #52 | Ongoing |
| The complete Osborne 1 reference ("the book") | #75 | Gated on the above |

---

## C. The `research`-labelled issues, and what closes each

| Issue | Title | State | What closes it |
|---|---|---|---|
| #1 | Phase 0 umbrella | Open | The list in §E |
| #3 | Disassemble Kaypro CoPower-88 CP/M loader | **Satisfied** | `copower88-protocol.md` + `research/copower88/kaypro/disasm/` |
| #4 | Disassemble Zorba `swpdos.td0`, diff vs Kaypro | **Satisfied** | Same doc + `zorba/disasm/pcdos.asm` |
| #5 | CoPower-88 port map & mailbox from the schematics | **Satisfied** | `copower88-schematics.md` + `copower88-protocol.md` |
| #6 | Drive C → GPIB protocol spec | Partially | The Drive C command set |
| #7 | RT-60A → RTC register map | Partially | A real unit, or a re-dump |
| #8 | Analyse `OCC1_HARDDISK.IMD` | Partially | Two products now identified (§B1); command sets remain |
| #30 | G2 multi-format diskette support | Open | Design work |
| #35 | `cpmtools` misreads Kaypro DSDD | Open | Optional upstream fix; superseded locally by `cpmfs.py` |
| #44 | Char-gen ROM variants | **Satisfied** | Both variants captured and catalogued (§B2) |
| #52 | Case + power research | Open | Ongoing design research |
| #64 | Index the Rev E schematic set + machine oracle | **Satisfied** | `o1-mainboard-schematic.md`, `tools/check_o1_map.sh` |
| #72 | Index the ROM source, re-derive the map | **Satisfied** | `o1-rom-source.md` |
| #73 | Nuevo + Osmosis prior art | Open | The write-up |
| #74 | Provenance TODOs | Open | User input on two items |
| #75 | The book | Gated | Everything above |
| #79 | Nuevo system disk does not boot | **Closed** | Not needed — the Nuevo path is not pursued (§B3) |
| #81 | OZROM as tooling | Partially | The appendices (C-5…C-7) and the column switch |
| #82 | Contribute OZROM to MAME | Open | A dump with acceptable provenance |
| #83 | A 2.0 ROM with CP/M resident | Open | Design + build + a no-disk boot test |
| #84 | Standalone Drive C reproduction | Open | Depends on #6 |

---

## D. Recommended close-outs

These seven issues have their deliverable in the repo and should be closed so the
list reflects reality — each with a comment pointing at the evidence:

- **#3, #4, #5** — the CoPower-88 research is consolidated in
  `docs/copower88-protocol.md` and `docs/copower88-schematics.md`. The one
  residual (doorbell/IRQ semantics) is now answerable from
  `research/roms/swp-p88.rom` and belongs with #23, not spread across three
  disassembly issues.
- **#44** — both character-generator variants are captured and catalogued.
- **#64** — the schematic set is indexed and the machine-level oracle exists and
  runs.
- **#72** — the ROM source is indexed and the memory/I/O map cross-checked
  against it.

---

## E. What is left before hardware design starts

Ordered by what blocks what:

1. **#39** — machine identities, board revisions and ROM markings (user action;
   unblocks gap 12 — the issue lists the three things actually worth reading).
2. **Finish Drive C's command set** from `DCL`/`DFD.SPR` (unblocks #6, #22, #84).
3. **Re-check `occ1-harddisk-analysis.md`'s port claim**, characterise the two
   hard-disk controllers, then pick the one to emulate (unblocks #8).
4. **#73** — write up the Nuevo and Osmosis boards as prior art (unblocks #30).
5. **#74** — close the two provenance TODOs (needs the user).

After that, #75 (the book) can start and #11/#12 (interposer design) have
everything they need.

---

## Appendix — decisions already taken

Kept here because they were reached by discussion and are not re-derivable from a
source:

- **All Osborne 1s are NMOS.** The CMOS Z84C00 shipped in 1985; O1 production
  ended in 1983. The interposer uses 74AHCT/HCT; the replica uses a modern CMOS
  Z84C00 deliberately.
- **The interposer gets its own 5 VDC feed** near the Z80 socket (~300 mA+).
- **Bank switching cannot be latched.** `ROM MODE*` is re-derived on every
  instruction fetch; a bank-2 access is only meaningful while the CPU is actually
  in bank 2 (`o1-memory-io-map.md` §4).
- **The interposer must never drive I/O addresses `0x00–0x03`** — any `OUT` there
  toggles the bank latch. The ROM never does it, and there is no software bank
  switch to model.
- **The `52-`/`80-`/`104-` floppy prefix is a label, not a bootability gate.** The
  display width is the machine's; the text layout is the CBIOS's
  (`mame-emulation.md` §4).
