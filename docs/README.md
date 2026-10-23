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
   (naming, convention, someone's forum post). Put the label beside the claim, in
   the doc that makes it: a hedge that names no evidence is not a confidence
   label, and an inference written down as a fact is indistinguishable from a
   measurement to the next reader.
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

`book/manifest.txt` carries a **second, coarser axis** — `solved | partial |
design | decision | reference | living | pending` — and it is not this one. It
says what *kind* of chapter a document becomes in the book (#75), not how
confident we are in it: a `design` chapter is normally a **Solved as a design**
doc, a `reference` chapter a **Solved** one, and `living` is the gap review. Read
them as two different questions and they cannot disagree.

## The docs

| Doc | Answers | Issues | State |
|---|---|---|---|
| `o1-memory-io-map.md` | Memory banks, I/O decode, bank switching, interrupts, connector pinouts, free I/O windows | #40, #62, #64, #72 | Solved — the port map, the three banks and the bank-switch mechanism are confirmed twice over (schematic + ROM source, then measured on the running machine), and the decode *granularity* below a 256-byte page is a schematic-level fact |
| `o1-mainboard-schematic.md` | Sheet-by-sheet index of the Rev E schematic set, device list, pinouts, the machine-level oracle | #62, #64 | Solved — every pinout the project builds against is read off the scan at native resolution and cross-checked under MAME, and what is not extracted is the discrete glue logic (above all the wait-state generator) |
| `o1-chargen-graphics.md` | The character generator's graphics set: the 33 graphics glyphs in the 2716 at **UA15**, that they are **block graphics, not line-drawing**, and the "64 columns" question answered by the video geometry | #97 | Partially solved — the set is identified and read straight off the ROM; the glyph-by-glyph mapping to Unicode codepoints is deliberately not written yet, because it has to be measured rather than asserted |
| `o1-rom-variants.md` | Every ROM image, CRC32s, the three MAME machines' ROM requirements, third-party ROM survey, and the personality-relevant ROM properties (IEEE-488 driver, video window) the firmware gate is built on | #70, #44, #86 | Solved as the ROM-identity authority — every CRC is re-derived from the bytes on every build, and what is not settled is interpretation rather than identity (four stock revisions undumped, one third-party label uncertain, one image's host-independence unconfirmed) |
| `o1-rom-source.md` | Index of the ROM 1.44 / CBIOS source, and the port map and interfaces it confirms | #72, #40 | Solved — the source is indexed and agrees with `o1-memory-io-map.md` §3, and `rom144.asm` reassembles to the shipped ROM byte for byte; the 1.41 CBIOS has never been diffed against a shipped system disk |
| `o1-rom-read-from-machine.md` | Reading the monitor ROM off a real Osborne 1: the sign-on's two lines and why only the upper one survives a faulty dim bit (so the revision is readable without any tool), why `DUMP`/`DDT` cannot see the ROM at all (it is banked out; `OUT (0)` selects it, and the program must live above `4000`), which tools are on which **single-density** shipping disk, a DDT-typable copy program, the exact fingerprint bytes per revision, and the `SETUP.COM` dead end | #205, #70 | Partially solved — the identification is settled and needs no tool; the copy is written down to the byte (§2, §4) but has not been run end to end, and there is no hardware route to a `NO_DUMP` slot |
| `rom-13-reconstruction.md` | The ROM 1.3 source disk read as what it is (an 8-inch 77-track FM/MFM disk with CP/M skew 3), the 19 files it holds, what the build needs that the disk does not carry (`OCCRAM2.ASM`, the `OCCTXT` systext), the two obstacles (`CCP` defined twice; `DBE`/`DCE` need **ACT 3.5E**), the `DBE`/`DCE` semantics recovered from the shipped rev-B ROM, and the control build that decides whether a 1.3 image may be called a reconstruction | #205, #72, #70, #203 | Partially solved — source extracted and indexed; the ROM is **not certified** and is blocked on a missing assembler |
| `o1-rom-2.0.md` | The **ROM 2.0 design** (#83): the **contents and the one number — 7695 bytes** for an interposer + ACB-4000 boot with no floppy ever read (§2.3, measured off `HARD.COM`), the 53-entry ROM jump table at `0100h` and the `ROMVEC+3N` contract that pins its numbering, the payload split and boot path, the 150-byte monitor budget, and the **feature set decided against OZROM's** — what to take and what to refuse (§4.8) | #83, #49, #72, #179, #24, #81, #22, #19, #29 | Partially solved — the ROM half is settled and measured (7695 bytes, the 53-entry jump table, the payload split, the 150-byte monitor budget, the feature set decided against OZROM's); the **hardware half is open** (no ROM 2.00 part exists; the window's address, paging and selector are #12's) |
| `rom-pico-protocol.md` | The ROM↔Pico channel and the boot screen — ROM 2.0's client: the banked window, `HCBOOT`, the hand-over, the 11-drive driver and the screen's mechanism | #247, #284 | Partially solved — the ROM side of #247 is built and measured (steps 1–7) and the firmware class that answers the door is written and host-tested (`firmware/rom-service/`); what is not closed is the swap, which still answers the door with `softrom_device`'s C++ stand-in |
| `mame-emulation.md` | Running the four machines — the three stock `osborne1` variants and this project's patched `osborne1nx` (#191) — ROM requirements, boot-disk compatibility, headless testing | #79, #24, #29, #191 | Solved — every machine boots what it should and the 3 × 3 disk matrix is measured; §7 names what is left (two unidentified bytes in the `-blank.imd` boot area, ROM 1.3 undumped, the Nuevo CBIOS 1.5 hang recorded rather than chased) |
| `osborne1nx-machine.md` | The fourth machine: the card that decodes the full 8-bit I/O address so the ACB-4000 host adapter answers on ports `30h`–`33h`, the disassembly the register model was read from, and the MD-10's on-disk header (§6) | #191, #178, #179 | Partially solved — the machine boots, the card answers and a transfer works; the DPB and drive tables are read out of `HARD.COM` at file offsets `0x998`/`0x9A8` rather than peeked (`md10-system.md` §9); what is left is the controller personality (#179), not the machine |
| `picoem-bridge.md` | **The picoem bridge**: a real RP2354B firmware binary running inside `rp2350-emu` and answering `osborne1nx`'s bus cycles — the answer to #192's open question (the emulator *does* expose an external GPIO/bus seam), why the pipe is a **FIFO and not the socket** the issue assumed, the 24-byte frame, the two ways the bus cycle is easy to get wrong, and **the seven picoem gaps** a stock Pico SDK binary runs into, each measured | #286, #192 | Partially solved — the acceptance passes (`tools/emulator-setup/mame-osborne1nx/picoem-check.sh`, seven checks); the bridge models **I/O cycles only** (a memory cycle is refused, §3), nothing exercises PIO, and the address bus is not driven to the firmware (§7) |
| `emulation-testbed.md` | **The emulation testbed**: the loop between MAME's `osborne1nx`/`osborne1nxp` and the RP2354B firmware in picoem; the **gap register for both emulators** — one row per gap, with its measurement, its cost and its owner; the six gates that close them; the definition of "a personality is emulation-complete"; and what **cannot** be emulated at all | #192, #286, #288, #179, #284 | Partially solved — the loop closes and Gate A is through it: the guest reads the firmware's byte (`picoem-guest-check.sh`, 12 PASS / 0 FAIL); what is left is M5 (a personality cannot yet tell *which register* a cycle is for, §4.1) and the pad mux (P5). §3 states **four facts** about the pinned picoem, three of which contradict a document or an issue in this tree |
| `ozrom-1e.md` | The OZROM 1E third-party monitor ROM as tooling: how to run it, its memory map, ROM jump table, keytable, the 52/80/104-column switch (mechanism measured from the ROM), its clock and memory tester | #81, #24, #29, #45, #7 | **Solved** — and #81 is closed on that deliverable. Two residues are routed: #167 (drive the column keys from the harness) and #168 (a complete Utilities disk) |
| `dd-upgrade-formats.md` | The DD upgrade's multi-format claim: the six formats, the CBIOS DPB+skew table that implements them, and the MAME acceptance test | #95, #30, #20 | **Solved** — mechanism proven from `occbio95.asm`; Osborne SD confirmed end to end in MAME. The four foreign formats are **taken as written** and not synthesised: the O1 does not need to recognise them (#95) |
| `drive-c-protocol.md` | Drive C (IEEE-488 RAM disk): the PIA↔bus line map, the host's frame, the two header bytes and the record address, the byte clock, the device contract, **the DPB and the capacity ceiling** | #6, #22, #84, #145 | **Solved** — measured from the disassembly *and* a trace of the real software; the DPB is read out of `DCL.COM` and matches the manual field for field |
| `drive-c-design.md` | The Drive C reproduction: hardware and firmware spec built on the contract | #84, #6, #22, #145 | **Solved as a design** — the shape is settled and unblocked (the P3 pinout, the P5 power budget and the DPB all came out of the archive); nothing is built, and what is left is a layout and firmware (§7) |
| `drive-c-executive.md` | The Drive C's **Executive variant** — and what both manuals' appendices actually say: `DFD.SPR` is a replacement CCP, the print-buffer budget, the capacity figures reconciling with the DPB, and the printer connector corroborating P3 | #84, #6, #145 | **Solved** — the Executive manual is a direct port of the Osborne 1 one; the hardware is one design for both machines |
| `occ1-harddisk-analysis.md` | The Osborne 1 hard-disk products: interface, files, command set | #8 | Solved — as a product analysis: the ACT's hardware interface is read out of its own BIOS image, and the storage decision went the other way (`harddisk-decision.md`); what remains is archival only |
| `harddisk-decision.md` | **The decision**: emulate the Adaptec ACB-4000 (the MD-10's controller), and the formal plan — the portable host-adapter design, the size / CP/M 2.2 ceiling, the sparse blob, and CoPower-88 coexistence | #8, #20, #27, #84, #178 | Solved — as a decision: one personality (ACB-4000 SCSI-1), plan in §9. **§7.3 was reversed**: the DPB **is** in the archive (`HARD.COM` file `0x9F0`), and §7.3 now leads with that; what is left is who copies the static tables into a running system (§10 item 1) |
| `acb4000-firmware.md` | The ACB-4000's own firmware: the ROM set, its internal machine, the command set (manual Table B-1), and why the MD-10 driver has no literal DPB | #178, #179 | Partially solved — the ROMs, the command set and the drive-table mapping are read; the geometry round-trip is inferred, not traced |
| `acb4000-host-adapter.md` | The ACB-4000's **host side**: the Z80-visible register protocol on ports `30h`–`33h` (the probe, a transaction, the four status bits), why the MAME-stub route is blocked by the O1's 2-bit I/O decode, and why a stock system image does not carry the low-RAM DPB tables | #178, #179 | Solved — the register protocol is decoded from the driver and both remaining routes are bounded; the four status bits' *names* are the one thing inferred |
| `acb4000-personality.md` | The **personality** (#179): the three layers as built and host-tested, the manual's two claims the code contradicts (`2F` is VERIFY not SEARCH; 18 sectors per track against the manual's 16), and what the end-to-end acceptance still needs | #179, #8, #178 | Partially solved — the three layers are built and host-tested; the end-to-end acceptance is not met, and the blocker is no longer the drive — `md10-system.md` is that memory map and the system boots to a prompt with three partitions. What is left is who copies the static DPB and descriptor tables into the running system |
| `md10-system.md` | The **MD-10's operating system**: how the vendor's own `PREP.COM` option 3 produces it, the recipe, what a drive carries (the label, the partition table in **both captured layouts**, the `E5h` directories), **the MD-10's memory map** (CCP `0xC200`, BDOS `0xCA00`, BIOS `0xD800`), the boot chain step by step, why `0x0559`–`0x055D` is not an unwritten block, **the 0x100 relocation error in the first captured system**, and **why PYXIS27 with three 15399-block partitions is the floor pin** (§9.1: one shared DPB, 7.5 MiB per partition), and **the block size, measured** (§9.3: `BSH=6` boots to `A0>`, halves the ALV to 121 bytes a drive, and puts 11 partitions of 8 MiB inside the 1451 bytes free) | #179, #178, #191, #198, #247 | **Solved** — the three-partition PYXIS27 drive boots to `A0>`, `B0>`, `C0>`, and `C:` takes a write and reads it back. `tools/research/md10prep.sh` produces a new geometry; `md10drive.py --layout md20` reproduces this one |
| `copower88-protocol.md` | CoPower-88 host protocol from the Kaypro + Zorba drivers | #3, #4, #5, #23 | Partially solved — the port pair, the handshake and the block transfer are read out of the two `RAMDISK.COM` builds; what is left is the 8088-side command set and the meaning of every status bit other than the two the drivers test |
| `copower88-schematics.md` | Walkthrough of SWP drawing 611-0003 (4 sheets) | #5 | Solved — the four sheets settle what the board is and how the host talks to it; what they do not settle is the second status bit the drivers poll and the base the Osborne variant's decode is set to |
| `rt60a-analysis.md` | The RT-60A: the register map **and the ABI contract** (pointer block, sentinel/invalidation rules), plus the O1's own native clock cells and OZROM's shape | #7, #18, #81 | Partially solved — the register map, the memory ABI and the sentinel rules are settled and are what `firmware/rt60a-rtc/` implements; the RT-60A's own IEEE-488 wake-up handshake is *retired* as a known unknown, to be reopened only if a unit or a good `CLOCK.COM` dump turns up |
| `o1-modem-serial.md` | MODEM (P1) and RS-232 (P2) interfaces, 6850 ACIA | #21, #56 | Solved — both connectors and their signals are read from the Technical Manual's own tables and confirmed against schematic sheet 7; the P1 header's physical orientation and the RXD receiver part are still open |
| `modem-tones.md` | **The modem's sound**: the carrier, the first negotiation signals in each direction and a two-second data phase for **300 (Bell 103A) / 1200 (Bell 212A/V.22) / 2400 (V.22bis) / 9600 (V.32)**, each frequency cited, the two scrambler polynomials, and the one thing that could not be confirmed (the scrambler preset) | #322, #56 | Solved — `tone.c` and its tests assert the tones, the rates and the ordering; the scrambler preset has no primary source (§8), and the V.22bis answer tone is a source disagreement taken as 2250 Hz (§5) |
| `o1-ieee488-port.md` | The IEEE-488 (GPIB) port: device-level behaviour, the eight ROM drivers, **the P3 pinout**, what the port does and does not implement, and a worked joystick interface on the data lines | #22, #84, #19 | Solved — the P3 pinout is transcribed from the Technical Manual and corroborated line for line by the ROM's own comment block; what is still open on P3 is electrical (the loading a device may present, §7) |
| `o1-upgrade-boards.md` | The four third-party 80-column upgrades (SCREEN-PAC, TRA, Nuevo, Osmosis) — and the fact that **no two attach, select a width or announce themselves the same way** | #73, #24 | Partially solved — each board's attachment, width selection and detection is read from its own material; what is left is one measurement and Osmosis's *technical* manual, which the archive does not hold |
| `floppy-adapter-design.md` | Switchable Gotek / physical-drive daughter card | #20, #62 | **Solved as a design** — every decision the design needed is made (§8) and the Rev A schematic is captured, wired, footprinted and checked; nothing is built and nothing is measured on hardware |
| `interposer-survey.md` | Prior art: open-source Z80 bus interposers, sniffers, ICEs — and **picoZ80/pico6502** (§1.6), a drop-in Z80/6502 CPU replacement whose cycle-accurate PIO bus interface is the closest prior art to the interposer's timing claim | #11, #17, #12, #259 | **Partially solved** — the survey is complete and every entry carries its licence, and **picoZ80/pico6502 (§1.6) is the closest prior art**; §8's licence finding stands: two of its "directly copyable" claims are GPL-3.0 / CC-BY-NC-SA and are not copyable. What is left is §3's level-shifting conflict against picoZ80's shipping board, one premise §7 must check, and one decision for the maintainer |
| `virtual-peripherals-block-diagram.md` | Bus and address-space allocation for the virtual peripherals | #12, #16 | **Solved as a design** — the bus position, the three taps, the banked ROM window, the memory window and the port-base strategy are settled, and the parts of them that touch the machine are measured; §7's personality *selection* is still a proposal, and nothing here is built |
| `mailbox-protocol.md` | The interposer's host↔firmware mailbox: the port pair, the command/reply framing, and the listing `MOUNT.COM` needs | #155, #27, #20, #18 | Open — this is a proposal, not a decision: nothing is built, and no number in it has been measured on hardware |
| `image-library-design.md` | **The image library**: the three media (external flash + one microSD + one USB stick) merged into one namespace, the `floppy/`/`disk/`/`printer/` layout, the KIND and size bands, the merge precedence, and the three protocol details writing the code settled | #283, #285, #192, #27, #181, #182 | Solved — the layout, the three media and the merge rule are the maintainer's decision of 2026-10-18 and the code behind them is written and host-tested (`firmware/library/`); the board's transports and the NOR flash's wear-levelling layer (§7) are not built, and nothing here has been measured on hardware |
| `fog-library.md` | The **FOG library compendium**: the First Osborne Group's user-group disk library, extracted and catalogued — 231 archives, 231 disks, 5,430 catalogue entries, every disk's own description, the compression-marker extensions explained, commentary on what is in it and why it exists, and the measured finding that the library records its own platform's decline (1985: 7 of 11 disks Osborne-specific; 1991: 4 of 10). Built from the extracted bytes, **not** from `fog-index.htm`, whose CRC column does not reproduce | #207, #208 | Solved — measured end to end from the extracted bytes (231 archives, 231 disks, 5,430 catalogue entries, 219/219 ARC members verified against the ARC's own CRC-16); what is not settled is two members of 5,987 that no decompressor recovers, and the 1,142 places where the disks' own pages and the disks disagree |
| `photo-survey.md` | Index of the project's own machine photographs | #9, #39 | Solved as a reference — all 16 frames in `research/pictures/` are indexed and 14 are read; two are not, and what they show is still unknown |
| `research-gaps.md` | **The status review**: every gap, where it stands, what is left | #1 | Solved — as a status review: every open research question is tracked with its evidence and what is left, cross-checked against the `research`-labelled issues |

## Subdirectories

| Path | Holds |
|---|---|
| `design/` | Generated artefacts — the O1NEXT concept PDF/SVG (#52) |
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
