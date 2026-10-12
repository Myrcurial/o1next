# docs/ — the analysis

Everything we have **concluded** about the Osborne 1, one Markdown document per
area. This file is the index and the house style for the directory.

## The three-way contract

| Where | Holds | Test |
|---|---|---|
| `research/` | **sources** — manuals, ROMs, disk images, photographs, with provenance | "would we lose the ability to do this work if the upstream link died?" |
| `docs/` | **conclusions** — what we worked out, and how we know | "can someone build against this without re-reading the raw material?" |
| GitHub issues | **work** — what is left, who is doing it, what closes it | "is there a unit of work here that can be finished and verified?" |

A doc should cite the `research/` files it derives from and the issues it
serves. An issue should cite the doc that will carry its result. Nothing should
exist in only one of the three.

## House rules

1. **Cross-references must resolve on the branch being merged.** If you cite
   `docs/foo.md` or `research/bar/`, that file has to exist on the branch the PR
   merges from — see AGENTS.md. Do not cite a doc you are about to write in a
   different PR.
2. **Never duplicate the archive.** Link into `research/` rather than copying
   scans, ROMs or images into `docs/`. The archive is provenance-tracked; a copy
   here is just drift.
3. **Say how you know.** Distinguish *measured* (a MAME run, a byte comparison),
   *read from a primary source* (schematic, ROM source, manual) and *inferred*
   (naming, convention, someone's forum post). The Z80 pinout table in
   `o1-memory-io-map.md` §6 was wrong for a day because an inference was written
   down as a fact.
4. **Cite the issue numbers** you serve, in the text (`#40`, `#62`), so the
   issue and the doc point at each other.
5. **Mermaid is welcome** for bus/state/timing diagrams.
6. **Tables beat prose** for pinouts, port maps, register maps and inventories —
   and give units and addresses in the same base throughout.

## Status vocabulary

Each doc should carry a one-line status near the top, using these words, so the
gap review (`research-gaps.md`) and the issues can be cross-checked quickly:

| Status | Means |
|---|---|
| **Solved** | The question is answered and the answer is checkable from the doc |
| **Partially solved** | The main shape is known; a named sub-question is not |
| **Open** | Not answered |
| **Superseded** | The question stopped mattering (better route found, hardware decision taken) |

## The docs

| Doc | Answers | Issues | State |
|---|---|---|---|
| `o1-memory-io-map.md` | Memory banks, I/O decode, bank switching, interrupts, connector pinouts, free I/O windows | #40, #62, #64, #72 | Solved (port map confirmed by the ROM source; decode *granularity* is schematic-level) |
| `o1-mainboard-schematic.md` | Sheet-by-sheet index of the Rev E schematic set, device list, pinouts, the machine-level oracle | #62, #64 | Solved |
| `o1-rom-variants.md` | Every ROM image, CRC32s, the three MAME machines' ROM requirements, third-party ROM survey, and the personality-relevant ROM properties (IEEE-488 driver, video window) the firmware gate is built on | #70, #44, #86 | Solved |
| `o1-rom-source.md` | Index of the ROM 1.44 / CBIOS source, and the port map and interfaces it confirms | #72, #40 | Solved |
| `mame-emulation.md` | Running the three machines, ROM requirements, boot-disk compatibility, headless testing | #79, #24, #29 | Solved |
| `ozrom-1e.md` | The OZROM 1E third-party monitor ROM as tooling: how to run it, its memory map, ROM jump table, keytable, the 52/80/104-column switch (mechanism measured from the ROM), its clock and memory tester | #81, #24, #29, #45, #7 | **Solved** — and #81 is closed on that deliverable. Two residues are routed: #167 (drive the column keys from the harness) and #168 (a complete Utilities disk) |
| `dd-upgrade-formats.md` | The DD upgrade's multi-format claim: the six formats, the CBIOS DPB+skew table that implements them, and the MAME acceptance test | #95, #30, #20 | **Solved** — mechanism proven from `occbio95.asm`; Osborne SD confirmed end to end in MAME. The four foreign formats are **taken as written** and not synthesised: the O1 does not need to recognise them (#95) |
| `drive-c-protocol.md` | Drive C (IEEE-488 RAM disk): the PIA↔bus line map, the host's frame, the two header bytes and the record address, the byte clock, the device contract, **the DPB and the capacity ceiling** | #6, #22, #84, #145 | **Solved** — measured from the disassembly *and* a trace of the real software; the DPB is read out of `DCL.COM` and matches the manual field for field |
| `drive-c-design.md` | The Drive C reproduction: hardware and firmware spec built on the contract | #84, #6, #22, #145 | Design — **unblocked**: the P3 pinout, the P5 power budget and the DPB all came out of the archive. What is left is layout, firmware and one bus-loading check |
| `drive-c-executive.md` | The Drive C's **Executive variant** — and what both manuals' appendices actually say: `DFD.SPR` is a replacement CCP, the print-buffer budget, the capacity figures reconciling with the DPB, and the printer connector corroborating P3 | #84, #6, #145 | **Solved** — the Executive manual is a direct port of the Osborne 1 one; the hardware is one design for both machines |
| `occ1-harddisk-analysis.md` | The Osborne 1 hard-disk products: interface, files, command set — and the corrected ACT port claim | #8 | Solved as a decision — the port claim is corrected, and the choice is made in `harddisk-decision.md` |
| `harddisk-decision.md` | **The decision**: emulate the Adaptec ACB-4000 (the MD-10's controller), and the formal plan — the portable host-adapter design, the size / CP/M 2.2 ceiling, the sparse blob, and CoPower-88 coexistence | #8, #20, #27, #84, #178 | **Decided** — one personality (ACB-4000); plan in §9; the drive-table record layout and its byte→field mapping are read (§7.2) |
| `acb4000-firmware.md` | The ACB-4000's own firmware: the ROM set, its internal machine, the command set (manual Table B-1), and why the MD-10 driver has no literal DPB | #178, #179 | Partially solved — the ROMs, the command set and the drive-table mapping are read; the geometry round-trip is inferred, not traced |
| `copower88-protocol.md` | CoPower-88 host protocol from the Kaypro + Zorba drivers | #3, #4, #5, #23 | Partially solved — residual doorbell/IRQ semantics |
| `copower88-schematics.md` | Walkthrough of SWP drawing 611-0003 (4 sheets) | #5 | Solved |
| `rt60a-analysis.md` | The RT-60A: the register map **and the ABI contract** (pointer block, sentinel/invalidation rules), plus the O1's own native clock cells and OZROM's shape | #7, #18, #81 | Solved as a contract — the hardware handshake is retired as a known unknown; `firmware/rt60a-rtc/README.md` implements the ABI |
| `o1-modem-serial.md` | MODEM (P1) and RS-232 (P2) interfaces, 6850 ACIA | #21, #56 | Solved |
| `o1-ieee488-port.md` | The IEEE-488 (GPIB) port: device-level behaviour, the eight ROM drivers, **the P3 pinout**, what the port does and does not implement, and a worked joystick interface on the data lines | #22, #84, #19 | Solved |
| `floppy-adapter-design.md` | Switchable Gotek / physical-drive daughter card | #20, #62 | Design |
| `interposer-survey.md` | Prior art: open-source Z80 bus interposers, sniffers, ICEs | #11, #17 | Solved — the survey is as complete as it will get; the materials are all in hand |
| `virtual-peripherals-block-diagram.md` | Bus and address-space allocation for the virtual peripherals | #12, #16 | Design |
| `mailbox-protocol.md` | The interposer's host↔firmware mailbox: the port pair, the command/reply framing, and the listing `MOUNT.COM` needs | #155, #27, #20, #18 | Design — a proposal; nothing is built |
| `photo-survey.md` | Index of the project's own machine photographs | #9, #39 | Reference |
| `research-gaps.md` | **The status review**: every gap, where it stands, what is left | #1 | Living document |

## Subdirectories

| Path | Holds |
|---|---|
| `design/` | Generated artefacts — the O1NG concept PDF/SVG (#52) |
| `mame-screens/` | Evidence screenshots from MAME runs, referenced by `mame-emulation.md` |

## Adding a doc

1. **Check whether an existing doc owns the area.** Extend it rather than adding
   a near-duplicate; `docs/` grew one document per *area*, not per question.
2. **Name it `<device>-<kind>.md`** — `protocol` (the contract a device speaks),
   `analysis` (what we worked out from a source), `design` (what we intend to
   build), `decision` (the choice taken, and its plan), `survey` (prior art).
   Kebab-case, lower case.
3. **Open with the status line**, then what the doc answers, then the sources.
4. **Add a row to the table above** in the same PR.
5. **If it closes a gap**, update `research-gaps.md` in the same PR.

## Relationship to the book

`#75` is the plan to assemble these documents into one coherent Osborne 1
reference once the research issues are closed. These docs stay the working
notes; the book is a consolidation pass, not a second source of truth. Write
them so they can be lifted into it — self-contained, sourced, and honest about
what is still unknown.
