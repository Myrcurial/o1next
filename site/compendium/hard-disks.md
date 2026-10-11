---
layout: page
title: "The hard-disk products"
subtitle: "Peripherals and storage · partially solved"
draft: "Draft &mdash; assembled from the working notes by `tools/build_book.py`. The source document is the authority; this page is a copy for reading, and it is regenerated from that source."
---

Source: research/harddisk/OCC1_HARDDISK.IMD (Osborne 1 SSDD, FM 10x256).
Extracted to research/harddisk/extracted/ via disk-analyse + cpmtools
(`osb1sssd`).

## What this is

The Osborne 1 hard disk product from **Australian Computer &
Telecommunications (ACT), (c) 1982** (string in BOOTHd.COM). This is the
"winchester style" interface — and, significantly for us, it is one of
the known **Z80-interposer** designs: the host-side hardware plugged
into the Osborne's Z80 socket.

## Two products, not one

The archive drop (#71) added a **second, unrelated** Osborne 1 hard-disk product,
so "the OCC1 hard disk" is a family, not a single thing:

| | ACT (this doc) | Media Distributing / Adaptec (**the MD-10**) |
|---|---|---|
| Source | [`research/harddisk/OCC1_HARDDISK.IMD`](https://github.com/Myrcurial/o1nextgen/blob/main/research/harddisk/OCC1_HARDDISK.IMD) | `research/adaptec/*.img` |
| Vendor string | `AUSTRALIAN COMPUTER & TELECOMMUNICATIONS  COPYRIGHT (C) 1982` | `Copyright (c) September 1983, Media Distributing` |
| Versions | `Version 31.05.82`, `Version 9-02-81` | `HARD version 1.93`, `PORTCHNG version 1.92`, `PREP version 1.93` |
| Controller | its own; prompts `Enter disk controller address (` | Adaptec ACB-4000; prompts `Enter starting port address in hex` / `must be on a 4 port boundary` |
| BIOS | `HARDBIOS.HEX`, overlaid by `LOADBIOS.COM` | `HARDBIOS.SPR`, `HARDBDOS.SPR`, `HARDCCP.SPR`, `HD00BIOS.SPR`, `HD04BIOS.SPR` |
| Other utilities | `MOVCPM10/5/F`, `DISKEDIT`, `DISKTEST`, `RESTORE`, `SAVEFILE` | `MD10.COM`, `MD20.COM`, `PREP.COM`, `DRIVETBL.DAT`, `PORTCHNG.COM` |

**The second product is identified: it is the Mega-byte MD-10.** Mega-byte Inc.'s
advertisement in *The Portable Companion* #5 (February/March 1983, PDF p. 25;
[`research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf`](https://github.com/Myrcurial/o1nextgen/blob/main/research/technical-articles/TPC-Issue05-1983-pp25-mega-byte-md10-hard-disk-ad.pdf))
sells the **MD-10** — 10 MB formatted for $2295, "20 and 44 megabyte Winchesters
also available" — and its footnote reads *"MD-10 is a registered trademark of
**Media Distributing**."* The disk in [`research/adaptec/`](https://github.com/Myrcurial/o1nextgen/blob/main/research/adaptec/) is copyright Media
Distributing (September 1983) and ships `MD10.COM`/`MD20.COM`, matching the 10
and 20 MB models, so the "Adaptec" disk is **MD-10 software**. Two details from
the ad bear on the interface question below: the MD-10 "does not tie up existing
OSBORNE ports" and is "significantly faster than other winchester subsystems
**which use the IEEE port**" — so it is **not** an IEEE-488 device, consistent
with a controller that claims its own addresses (hence `PORTCHNG.COM`) rather
than borrowing the serial/video ports. Its own parts list — "drive controller,
case, power supply, cabling, **Z-80 interface**" — points at the same class of
host attachment as the ACT unit: a **Z80-socket or dedicated-port** design, not
the IEEE bus.

Both are **port-relocatable** controllers: the ACT disk asks for a "disk
controller address", the Adaptec disk for a "starting port address … on a 4 port
boundary", and it ships `PORTCHNG.COM` to change it. That is consistent with the
rest of the O1, whose I/O decode only looks at the low address lines.

It also means the port claim in "Hardware interface" below should be re-derived
rather than trusted: `0x2A00` and `0x2C01` are the serial ACIA and the video PIA
on this machine, so either the ACT adapter is mapped elsewhere or that
disassembly read the wrong operand.

So there are **three** routes to more storage than 2 × 182 KB — the two hard disks
here, and Drive C ([`docs/drive-c-protocol.md`](https://github.com/Myrcurial/o1nextgen/blob/main/docs/drive-c-protocol.md)) — and only Drive C is buildable
without unobtainable hardware (#84).

## Files

| File | Role |
|---|---|
| HARDBIOS.HEX | Intel HEX of a full replacement BIOS, loads at 0xDF00-0xEB00 (17-jump BIOS entry table at 0xDF00) |
| LOADBIOS.COM | Overlays HARDBIOS.HEX onto the running BIOS ("Your BIOS has been overlayed"; validates 17 JMPs, checksums, warm-boot vector) |
| BOOTHd.COM | Hard-disk boot ("ERROR DURING BOOTING TO HARD DISK") |
| MOVCPM10/5/F.COM | MOVCPM variants (10MB / 5MB / full? volume sizing) for relocating CP/M under the new BIOS |
| DISKEDIT.COM, DISKTEST.COM | Winchester utilities |
| RESTORE.COM, SAVEFILE.COM | Backup/restore to floppy |
| AUTOST.COM, SYSGEN.COM, PIP.COM, XDIR.COM | Standard |

## Hardware interface (from HARDBIOS.HEX disassembly)

- Same Osborne bank discipline as Drive C: **OUT (0x00) = bank 2 (IO),
  OUT (0x01) = bank 1 (RAM)**, DI/EI bracketed (subroutines at 0xEA6A /
  0xEA75 wrap all IO accesses).
- Device registers are memory-mapped in bank 2:
  - **0x2A00** — command/data register (written with a command byte
    after bank select)
  - **0x2C01** — status register (read; bit 5 (0x20) = status flag
    tested after rrca; merged into a saved status byte)
- Also `OUT (C),A` with port value cached at 0xEF08 — indirect port
  write, target TBD (possibly NMI control or bank-related).
- The BIOS preserves a full register environment (pushes IX/IY/HL/DE/
  BC/AF, switches to a private stack at 0xEFC1) around hard-disk calls
  — it hooks deep into the 17-entry BIOS jump table as a full BIOS
  replacement, not just a disk-driver wedge.

## Comparison with Drive C

| | Drive C (RAM disk) | ACT hard disk |
|---|---|---|
| Physical interface | IEEE-488 port (6821 PIA bit-bang @ 0x2900-0x2903) | Custom host adapter, regs @ 0x2A00 / 0x2C01 |
| Host code | Driver wedge (DCL/DFD.SPR) | Full BIOS replacement @ 0xDF00 |
| Boot | QUICKPAC autoload from floppy | BOOTHd.COM + SYSGEN to winchester |

## Implications for the interposer project

1. **The ACT product validates the whole interposer concept on this
   exact machine** — a Z80-socket interposer was a shipping commercial
   Osborne 1 peripheral in 1982.
2. Its register interface (0x2A00 command/data, 0x2C01 status) is a
   clean, tiny target: a Pico 2 W could emulate the ACT host adapter
   purely in bank-2 memory space, no PIA bit-banging needed.
3. For the mass-storage personality we therefore have two documented
   paths: emulate the Drive C GPIB RAM-disk protocol (docs/drive-c-
   protocol.md), or emulate the ACT adapter (this note). The ACT path
   looks simpler electrically but needs the interface hardware
   reverse-engineered (photos / unit access); the Drive C path is
   fully observable from software alone.

## Open questions

1. Which ACT product exactly (model no./capacity)? MOVCPM10 vs
   MOVCPM5 suggests 10MB and 5MB volume support.
2. Command set at 0x2A00 (sector read/write/format, geometry
   reporting) — needs annotated disassembly of the HARDBIOS driver
   routines around 0xE000-0xEA0A.
3. The `OUT (C)` target port at 0xEF08.
4. Whether any ACT hardware photos/schematics survive online.
5. **Re-derive the port claim.** `0x2A00`/`0x2C01` are the serial ACIA and the
   video PIA, and both hard-disk products describe their controller port as
   *configurable* — so the addresses in "Hardware interface" above need checking
   against the ACT disk's own prompt and stored value before they are relied on.
6. **The second product** (Media Distributing / Adaptec ACB-4000): its command
   set, its default port, and what `DRIVETBL.DAT` contains. See "Two products,
   not one" above.
