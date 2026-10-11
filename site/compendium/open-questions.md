---
layout: page
title: "Open questions"
subtitle: "The project · living document"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

**Last reviewed:** 2026-10-11 (fourth pass), after **#6 and #7 were closed** — #6
on its stated deliverable ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md), validated end to end), with
its residue moved to #84; #7 because the clock ABI *is* its deliverable and #18
owns the implementation. Phase 0 now reads **17 of 23**. Previous review
2026-10-11 (third pass), after #6's transport and device contract were measured
and validated and [`docs/drive-c-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-design.md) (#84) became the build spec. Previous
review 2026-10-11 (later pass), after #95 was answered from the OCC
CBIOS source, #7's clock ABI was written as a contract, #81's OZROM index was
built, and #6's `DFD.SPR` blocker was re-characterised. Previous review
2026-10-11, after the *Portable Companion* extract batches
(#73), the issue triage that re-scoped this doc's subject list, and the Phase-0
sub-issue tree (§F). Previous review 2026-10-10, after the archive drop (#71),
the ROM-source indexing (#72) and the MAME work (#79).

This is the single place that says, for every open research question, **whether
it is answered, by what evidence, and what is left** — cross-checked against the
`research`-labelled issues. When the two disagree, one of them is wrong.

**Status words** (same vocabulary as [`docs/README.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/README.md)):

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
2. ~~**Drive C's command set**~~ — **closed 2026-10-11 (#6).** The transport and
   the device contract are measured from the disassembly *and* a trace of the real
   software, and a model of the box makes the 1983 loader complete and PIP write
   to `C:`. The DPB came out of `DCL.COM` (#145), and `DFD.SPR` turned out to be a
   replacement CCP rather than the transport, so the disassembly it was waiting on
   is off every critical path. What is left is **#84's**, not research's: how the
   box resolves banks 0–2 (hardware-gated) and whether Drive C, the printer at
   device 3 and the RT-60A can share one bus. The build spec is
   [`docs/drive-c-design.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-design.md).
3. **The hard-disk controller decision (#8)** — two products are characterised;
   pick the one worth emulating before any personality code is written.
4. ~~**The RT-60A ABI (#7)** — decide the contract, then implement it in #18.~~
   **Done 2026-10-11.** The ABI is written as a contract in `rt60a-analysis.md`
   (pointer block, sentinel/invalidation rules) and #18 implements it. The
   hardware handshake is retired as a known unknown.
5. ~~**Does the DD upgrade read foreign formats? (#95)**~~ **Solved 2026-10-11
   from the OCC CBIOS source**: a DPB + sector-skew table (`occbio95.asm`) whose
   capacities match the manual's list exactly, selected by a monitor-ROM density
   probe. `dd-upgrade-formats.md`; Osborne SD confirmed end-to-end in MAME.
6. ~~**OZROM 1E as tooling (#81)**~~ **Solved 2026-10-11**: `ozrom-1e.md` indexes
   the manual and measures it on all three machines.

Everything else is either done, or is research that can proceed in parallel.
**#79 is closed and no longer blocking**: the decision taken is not to chase the
Nuevo path, and to build the video personality from the ScreenPac design plus
OZROM's soft 52/80/104-column switch.

---

## A. The original gaps

| # | Gap | Status | Evidence | Issues | What's left |
|---|---|---|---|---|---|
| 1 | Exact memory & I/O map, free decode windows | **Solved** | `o1-memory-io-map.md` §2–§7 (schematic), confirmed from the ROM source in `o1-rom-source.md`, measured on the running machine by [`tools/check_o1_map.sh`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_o1_map.sh) | #40, #62, #64, #72 | Decode *granularity* is still schematic-level. Free gaps between the five device blocks: `2300–28FF`, `2B00–2BFF`, `2D00–2FFF` |
| 2 | NMOS vs CMOS Z80 across the target machines | **Superseded** | Resolved by history: the CMOS Z84C00 shipped in 1985, O1 production ended in 1983 — every O1 is NMOS. Interposer standardised on 74AHCT/HCT | #39 | #39's remainder: machine IDs and date codes, for the record |
| 3 | Z80 socket **and** char-gen socket pinout | **Solved** | Z80: datasheet, schematic sheet 3 of 9, [`tools/check_schematics.py`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_schematics.py). UA15: read at 1200 dpi off **sheet 4 of 9** (not the video sheet) — plain Intel 2716 pinout, `/CE`+`/OE` grounded, pin 21 strapped +5 V; address = `(scan<<7) \| char`; outputs serialised by UA14 (74166). `o1-mainboard-schematic.md` §4a, `o1-memory-io-map.md` §6, asserted in [`tools/check_schematics.py`](https://github.com/Myrcurial/o1nextgen/blob/main/tools/check_schematics.py) | #62, #24, #64 | — |
| 4 | CoPower-88 monitor ROM dump | **Superseded** | The SWP co-processor ROM is **in the repo**: [`research/roms/swp-p88.rom`](https://github.com/Myrcurial/o1nextgen/blob/main/research/roms/swp-p88.rom), 8088 code, from Maslin's archive. The board and interposer are common across hosts; only the driver varies | #3, #4, #5, #70 | Confirm the residual doorbell/IRQ semantics *from that ROM* rather than by inference |
| 5 | Power budget | **Solved** | Decision taken: the interposer gets its own 5 VDC feed near the Z80 socket, sized for Pico 2 W bursts (~300 mA+) | #12 | — |
| 6 | CoPower-88 protocol | **Partially** | `copower88-protocol.md` (Kaypro↔Zorba driver diff), `copower88-schematics.md` (SWP 611-0003), plus the 8088 ROM | #3, #4, #5, #23 | Doorbell/IRQ semantics; the 611-0003 sheet-4 comparator reference value; consolidate into one authoritative spec |
| 7 | Drive C IEEE-488 protocol | **Solved** | `drive-c-protocol.md`; `DRIVE_C.IMD` extracted and disassembled ([`research/drive_c/disasm/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/drive_c/disasm/)); the ROM's IEEE-488 implementation gives the PIA programming, the GPIB command bytes and the "always ready" stub behaviour (`o1-rom-source.md`); and the **byte transport is now read from `DCL`** — PIA init, the 128-byte strobed transfer, the operation bytes `88h`/`81h`, port B bit 6 as the device status input. The transport is in `DCL`, **not** `DFD.SPR` (which makes no PIA references at all); and the **port's own semantics are now documented from the vendor's side** — `o1-ieee488-port.md` (Companion #8): **eight** low-level ROM drivers, **15** devices on the bus (**8** if parallel poll is used), the machine's own address is **0**, and the driver table is the eight 3-byte jumps at **`013F–0156`** | #6, #22, #84 | — **#6 closed 2026-10-11.** The two residues are #84's now: bank resolution for `n = 0,1,2` (hardware-gated) and the GPIB device-address question. The manual settles one thing: real GPIB protocol is *not* supported on the Drive C connector |
| 8 | RT-60A register map | **Solved** (as a contract) | `rt60a-analysis.md`, reconstructed from the manual | #7, #18 | **Decision taken 2026-10-11 (#7): implement the ABI, not the hardware.** The manual documents the memory contract (`0x0040` pointer, the block, the `0xEFF8` vector) and does *not* document the IEEE handshake — so faithful-hardware emulation is blocked on a `CLOCK.COM` we cannot read, and buys nothing the ABI does not. Left: ~~promote the map to a contract, then implement it in #18.~~ **The map is promoted to a contract** and #18 implements it — **#7 closed 2026-10-11**. The bitsavers TD0 is still a damaged dump (27 no-id sectors) |
| 9 | OCC1 hard disk | **Partially** | `occ1-harddisk-analysis.md`; the archive drop showed there are two distinct products, not one; and the Media Distributing one is now **named** — it is the **MD-10** (§B1) | #8 | **Now a decision, not a question** (#8): pick the cheapest controller to emulate — one personality, not two. Left: the command sets, the default port, and a re-check of the doc's `0x2A00`/`0x2C01` claim (those are the ACIA and video PIA addresses, so something there is misread) |
| 10 | 6850 ACIA location for the WiFi modem | **Solved** | `o1-memory-io-map.md` §3: `2A00`/`2A01`, UC4 — confirmed independently by the ROM source | #21 | — |
| 11 | Floppy controller, port map, DD changes | **Partially** | Ports `2100–2103` and the full WD179x command set from the ROM source; 1.44 *is* the DD ROM; DD block = 1K; the Nuevo and Osmosis DD boards are documented | #20, #30, #73 | MB8877 vs WD1793 (schematic-level); the DD upgrade's electrical changes |
| 12 | Which three machines, which board revisions | **Open** | — | #39 | **User action**: machine IDs (one is 24187A) and Z80 markings |
| 13 | A known-good boot disk per machine | **Solved** | Measured 3×3 matrix in `mame-emulation.md` §4: all three `-blank.imd` system disks boot on all three MAME machines; diagnostics disks also archived | #29, #70 | The *Nuevo system* disk (`OS1NUEVO.IMD`) does not boot — #79, closed as not needed — but the gap as stated is met |
| 14 | Consolidate into per-device protocol specs | **Partially** | Done: `copower88-protocol.md`, `drive-c-protocol.md`, `rt60a-analysis.md`, `o1-rom-source.md`, `o1-rom-variants.md`, `mame-emulation.md` | #75 | Missing: floppy, hard disk, printer/parallel, keyboard. #75 (the book) is the final consolidation |
| 15 | Memory-resident vs pure I/O-port for virtual devices | **Solved** | Recommendation stands: pure I/O-port, in the free windows from gap 1 (`o1-memory-io-map.md` §7) | #12, #16 | Same decode-granularity caveat as gap 1 |

---

## B. Questions that appeared since the original review

### B1. Hard-disk products — two in the archive, and seven routes advertised in total

The original gap 9 assumed a single OCC1 hard disk. The archive drop (#71) turned
up a second, unrelated one. Confirmed from their own strings:

| | ACT hard disk | Media Distributing / Adaptec |
|---|---|---|
| Source | [`research/harddisk/OCC1_HARDDISK.IMD`](https://github.com/Myrcurial/o1nextgen/blob/main/research/harddisk/OCC1_HARDDISK.IMD) | `research/adaptec/*.img` |
| Vendor string | `AUSTRALIAN COMPUTER & TELECOMMUNICATIONS  COPYRIGHT (C) 1982` | `Copyright (c) September 1983, Media Distributing` |
| Versions | `Version 31.05.82`, `Version 9-02-81` | `HARD version 1.93`, `PORTCHNG version 1.92`, `PREP version 1.93` |
| Controller | its own; `Enter disk controller address (` | Adaptec ACB-4000; `Enter starting port address in hex`, `must be on a 4 port boundary` |
| Utilities | `BOOTHD`, `LOADBIOS`, `HARDBIOS.HEX`, `MOVCPM10/5/F`, `DISKEDIT`, `DISKTEST`, `RESTORE`, `SAVEFILE` | `MD10.COM`, `MD20.COM`, `HARD.COM`, `HARDBIOS.SPR`, `HARDBDOS.SPR`, `HARDCCP.SPR`, `HD00/HD04BIOS.SPR`, `PREP.COM`, `PORTCHNG.COM`, `DRIVETBL.DAT` |

So the three routes **represented in the archive** are the **ACT hard disk**, the
**Media Distributing/Adaptec hard disk**, and **Drive C** (IEEE-488). Both
hard disks use a *port-relocatable* controller — which matters, because the O1's
I/O decode is sloppy, so "4 port boundary" is the same two-address-line decode the
rest of the machine uses.

**Four more routes appear only in the magazine archive**, with no software or media
of ours behind them — recorded because a survey of "what storage existed" is
incomplete without them, and because none is buildable from what we hold:

- **Corvus hard disks**, reached through a link program — `CLINK2`, built from
  `CLINK2K2.ASM` and assembled by the owner with `ASM.COM` and `LOAD.COM`. *The
  Portable Companion* #11 (October 1983), PDF p. 54 = printed p. 52, "**Doubling
  hard disk memory**" by Bob Gras (reprinted from the OSUG newsletter, Anchorage),
  is a patch for exactly that program, needed because DD leaves less memory for
  it ([`docs/dd-upgrade-formats.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/dd-upgrade-formats.md)). No Corvus software or media held.
- **Osmosis OSMOS 7**, advertised as "Winchester disks … 5¼, 10½, 15¾ & 21 MByte
  units - a 42 Megabyte max capacity", $2475–$3650 — on the same page as the
  OSMOS 5 80-column board, which itself "**includes a Hard Disk interface for
  future plug-in expansion**" ([`docs/o1-upgrade-boards.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/o1-upgrade-boards.md)). No media held.
- **Trantor TSL-5 / TSL-10** — *The Portable Companion* #5 (February/March 1983),
  PDF p. 28: "unpack your disk, **plug it into the IEEE port**, run a simple 5
  minute installation procedure", 5 MB $2995 / 10 MB $3395, supplied with BIOS,
  back-up and retrieve utilities and cable
  ([`research/technical-articles/TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp28-trantor-tsl-hard-disk-ad.pdf)).
  This is the line [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md) records the Drive C vendor as
  reselling at a discount; the advertisement is what pins its interface to the
  **IEEE bus**. No media held.
- **Helix** (Micro Computers of New Orleans) — *The Portable Companion* #5,
  PDF p. 98, "**Winchesters Now Available For The Osborne 1**", 5/10/15 MB at
  $2500/$3000/$3500, a "**Z-80 adaptor** card [that] leaves external ports free"
  and a ribbon cable that "disconnects for portability"
  ([`research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp98-tra-80-100-column-video-and-winchester-ads.pdf)).
  No media held.

**One of the two archived products now has a name.** The Mega-byte Inc.
advertisement in *The Portable Companion* #5 (PDF p. 25) sells the **MD-10** —
10 MB formatted for $2295, "20 and 44 megabyte Winchesters also available" — and
its footnote reads *"MD-10 is a registered trademark of **Media Distributing**."*
That is the same Media Distributing whose September-1983 disk sits in
[`research/adaptec/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/adaptec/), and that disk ships `MD10.COM`/`MD20.COM`, matching the 10
and 20 MB models. So the archive's "Media Distributing / Adaptec" entry **is the
MD-10**, with an Adaptec ACB-4000 controller inside
([`docs/occ1-harddisk-analysis.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/occ1-harddisk-analysis.md)). The ad also fixes the *architecture*: the
MD-10 "does not tie up existing OSBORNE ports" and is "significantly faster than
other winchester subsystems **which use the IEEE port**" — i.e. it is **not** an
IEEE-488 device, unlike Trantor, Drive C and the RT-60A. Taken with the ACT
unit's Z80-socket interposer and Helix's "Z-80 adaptor card", that is a pattern
worth recording for #84: **several vendors reached the Osborne 1's storage
through the CPU socket or a port of their own, not through IEEE.**

So the honest count is **seven** advertised storage routes beyond the floppies —
ACT, Media Distributing/Adaptec (**the MD-10**), Drive C, Corvus, OSMOS 7,
Trantor TSL-5/TSL-10 and Helix — of which only **Drive C** is buildable from what
this project holds (#84).

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
| Nuevo + Osmosis upgrade boards as prior art (two products each; neither matches OCC's implementation) | #73 | **Video half written up**; the DD halves of both products, and how each lets software detect the board, are outstanding |
| Advent Products' **Osbaud** baud-rate generator (#21) | #21 | The four connection points are decoded from the review + schematic (6850 pins 4/12, 74LS32 and 74LS04 pin 7); the internal crystal/divider topology is **not** known — needs the instruction sheet or a photo. `o1-modem-serial.md` |
| Archive provenance TODOs (2 items) | #74 | **Closed** |
| `cpmtools` misreads Kaypro DSDD images | #35 | `misc`. Upstream identified: the primary site is `moria.de` (Michael Haardt, 2.23, **email patch** — no GitHub, no tracker), and the practical PR venue is the unofficial `lipro-cpm4l/cpmtools` fork (3 open PRs, 2.21-based). Closes **when filed**, not when merged |
| G2 multi-format diskette read/write | #30 | **Closed** — folded into #95 |
| Case + power research (the LFF and SFF boards, and the O1NG enclosure) | #52 | **Phase 5** (#49). A design task, not Phase-0 research |
| Contribute OZROM 1E to MAME (BIOS slot or an `osborne1oz` machine) | #82 | `misc`. The **machine definition may be worth more than the dump**; a physical OZROM 1E is available to read, which would at least give honest provenance |
| A local Jekyll environment | #106 | `misc`. `site/` has **no `Gemfile`**, so this is partly creating the manifest, not just resolving it |
| `Osborne1ng.ttf` — a complete modern font | #107 | `misc`. Extrapolate the O1's 8x10 forms into a full modern face with accents |
| The complete Osborne 1 reference ("the book") | #75 | **Ungated** — a rolling build; pieces tracked as #108–#115 |

---

## C. The `research`-labelled issues, and what closes each

After the 2026-10-11 triage the label means **reverse engineering and
documentation** again. Five issues left it: **#35** and **#82** (`misc` — upstream
contributions), **#97** (`misc` — site and font), **#84** (a build, now
[`hardware/drive-c/`](https://github.com/Myrcurial/o1nextgen/blob/main/hardware/drive-c/)) and **#52** (Phase 5). **#83** was never
research-labelled and has been removed from this table.

| Issue | Title | State | What closes it |
|---|---|---|---|
| #1 | Phase 0 umbrella | Open | The sub-issue tree (§F) — 15 of 23 closed |
| #6 | Drive C → GPIB protocol spec | ~~Largely~~ **Closed 2026-10-11** | Delivered as [`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md) and validated end to end. The residue moved to **#84** — bank resolution for `n = 0,1,2`, and the GPIB device-address question |
| #7 | RT-60A → a time **ABI**, not the hardware | ~~Partially~~ **Closed 2026-10-11** | The ABI *is* the deliverable and it is written in `rt60a-analysis.md`; #18 implements it |
| #8 | Choose which hard-disk controller to emulate | Partially | A written recommendation — one personality, not two |
| #73 | Nuevo + Osmosis prior art | Partially | The DD halves of both products, and the board-detection method |
| #75 | The book | **Ungated** | The pieces in #108–#115 |
| #81 | OZROM as tooling | Partially | The column-switch mechanism; appendices C-5…C-7 |
| #95 | DD multi-format (now also the G2, absorbed from #30) | Partially | The MAME test matrix — read **and** write |

Closed, but still carrying the label — the work that got Phase 0 to where it is:
**#2, #3, #4, #5, #6, #7, #9, #10, #30, #44, #64, #70, #71, #72, #74, #79**. They are
attached to #1 as sub-issues, so the parent's progress bar counts them.

---

## D. Triage decisions taken 2026-10-11

This section used to be a "recommended close-outs" list. **It has been done** —
#3, #4, #5, #44, #64 and #72 are all closed — so it now records the *decisions*
from the issue triage instead, because they are reached by discussion and are not
re-derivable from a source:

- **#30 folded into #95.** Same question one product apart: the DD half is already
  answered in `dd-upgrade-formats.md` from the DD upgrade manual, and the G2
  format table moves to that doc.
- **#35 and #82 stay open, as `misc`.** They are upstream contributions, not
  reverse engineering — and #35 is a genuine courtesy fix now that `cpmfs.py`
  gives us a known-good oracle to diff against.
- **#7 re-scoped to an ABI.** Implement the *documented* memory contract, not the
  *undocumented* IEEE handshake (see §A gap 8).
- **#8 re-scoped to a decision.** Which controller to emulate — one personality,
  not two.
- **#97 keeps the machine's own repertoire** — the graphics-set Unicode mapping
  and the recovered logo art. The modern font is split out as **#107**
  (`Osborne1ng.ttf`).
- **#84 is a build**, filed beside the other standalones (#47, #56) in
  [`hardware/drive-c/`](https://github.com/Myrcurial/o1nextgen/blob/main/hardware/drive-c/), not under the interposer.
- **#52 belongs to Phase 5** (#49).
- **The book is ungated.** #75 no longer waits on every research issue; it is a
  rolling build (#108–#115), with Part I and the appendices buildable today.

---

## E. What is left before hardware design starts

Ordered by what blocks what:

1. **#39** — machine identities, board revisions and ROM markings (user action;
   unblocks gap 12 — the issue lists the three things actually worth reading).
2. ~~**Finish Drive C's command set** from `DCL`/`DFD.SPR`.~~ **Done 2026-10-11
   (#6 closed)** — the protocol, the DPB and the capacity ceiling are in
   `drive-c-protocol.md`, and the **P3 pinout** came out of the Technical Manual
   already in the archive (`o1-ieee488-port.md` §6). The `DFD.SPR` disassembly
   came *off* the list rather than onto it: it is a replacement CCP, which a
   reproduction inherits. The bank-resolution question is hardware-gated and now
   sits on **#84**.
3. **Decide the hard-disk controller** (#8): characterise both, pick one to
   emulate, and correct `occ1-harddisk-analysis.md`'s port claim.
4. ~~**Write the RT-60A ABI contract** (#7), then implement it in #18.~~ **Written
   2026-10-11** (`rt60a-analysis.md`); #18 implements it.
5. **#73** — the DD halves of the Nuevo and Osmosis boards.

The book (#75) is **no longer gated on all of this**: it is a rolling build whose
pieces are tracked as #108–#115, and Part I plus the appendices are buildable now.
#11/#12 (interposer design) have everything they need.

---

## F. The issue tree (added 2026-10-11)

Phase 0 was an umbrella with **no children**, so "how close is Phase 0?" was
unanswerable from the issue list. Every phase parent now carries a sub-issue
tree, **closed issues included**, so each one renders a progress bar:

| Phase parent | Children | Closed |
|---|---|---|
| **#1** — Phase 0: research & reverse engineering | 23 | 17 |
| **#11** — Phase 1: interposer hardware (+ the standalone adapters #47, #56, #84) | 8 | 0 |
| **#16** — Phase 2: firmware personalities | 11 | 1 (#86) |
| **#25** — Phase 3: Osborne-side software | 4 | 0 |
| **#29** — Phase 4: on-hardware validation | 0 | — |
| **#49** — Phase 5: the reproduction | 1 (#52) | 0 |
| **#75** — the book | 8 (#108–#115) | 0 |

Two conventions came out of this, and both are worth keeping:

- **Closed work stays attached.** #2, #3, #4, #5, #6, #7, #9, #10, #30, #40, #44,
  #64, #70, #71, #72, #74 and #79 are children of #1. The progress bar is the
  point: Phase 0 is three-quarters done and should read that way.
- **`misc` is the label for work that is not a phase** — upstream contributions
  (#35, #82), the site (#97), build tooling (#106) and the modern font (#107).
  Everything else belongs to a phase, and to a parent.

The rule that keeps it honest: when an issue is opened, closed or re-scoped, the
tree and this table move in the same PR — the same way a doc row does.

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
